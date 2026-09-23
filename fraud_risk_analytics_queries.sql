-- ============================================================
-- FINTECH FRAUD & RISK ANALYTICS
-- Principales consultas SQL del proyecto
-- Motor: MySQL 8.x
-- Base: fintech_fraud
-- Período: julio 2025 - junio 2026
--
-- IMPORTANTE:
-- El dataset no contiene fraude confirmado ni una tabla original
-- de alertas. Las consultas generan señales analíticas simuladas
-- y un Risk Score heurístico para priorización.
-- ============================================================

-- ============================================================
-- 1. PERFIL DE RIESGO POR CLIENTE
-- Señales: velocity, operaciones grandes, anomalías, dispositivos
-- utilizados y dispositivos compartidos.
-- ============================================================

WITH operaciones AS (
    SELECT
        t.transaccion_id,
        t.cliente_id,
        t.dispositivo_id,
        t.fecha_hora,
        t.monto,
        LAG(t.fecha_hora) OVER (
            PARTITION BY t.cliente_id
            ORDER BY t.fecha_hora, t.transaccion_id
        ) AS transaccion_anterior
    FROM transacciones t
),
indicadores AS (
    SELECT
        cliente_id,
        dispositivo_id,
        transaccion_id,
        fecha_hora,
        monto,
        TIMESTAMPDIFF(
            MINUTE,
            transaccion_anterior,
            fecha_hora
        ) AS minutos_desde_anterior
    FROM operaciones
),
estadisticas AS (
    SELECT
        cliente_id,
        AVG(monto) AS monto_promedio_cliente,
        STDDEV(monto) AS desviacion_cliente
    FROM transacciones
    GROUP BY cliente_id
),
clientes_dispositivos AS (
    SELECT
        dispositivo_id,
        COUNT(DISTINCT cliente_id) AS clientes_distintos
    FROM transacciones
    GROUP BY dispositivo_id
)
SELECT
    i.cliente_id,
    COUNT(*) AS operaciones_totales,
    SUM(CASE WHEN i.minutos_desde_anterior <= 10 THEN 1 ELSE 0 END) AS operaciones_rapidas,
    SUM(CASE WHEN i.monto >= 100000 THEN 1 ELSE 0 END) AS operaciones_grandes,
    SUM(CASE WHEN i.monto >= 100000 THEN i.monto ELSE 0 END) AS monto_operaciones_grandes,
    COUNT(DISTINCT i.dispositivo_id) AS dispositivos_utilizados,
    MAX(cd.clientes_distintos) AS max_clientes_por_dispositivo,
    SUM(
        CASE
            WHEN s.desviacion_cliente > 0
             AND i.monto > s.monto_promedio_cliente + (2 * s.desviacion_cliente)
            THEN 1 ELSE 0
        END
    ) AS operaciones_anomalas,
    MAX(
        CASE
            WHEN s.desviacion_cliente > 0
            THEN (i.monto - s.monto_promedio_cliente) / s.desviacion_cliente
            ELSE NULL
        END
    ) AS z_score_maximo
FROM indicadores i
JOIN estadisticas s ON i.cliente_id = s.cliente_id
LEFT JOIN clientes_dispositivos cd ON i.dispositivo_id = cd.dispositivo_id
GROUP BY i.cliente_id
HAVING operaciones_rapidas >= 5
    OR operaciones_grandes >= 3
    OR operaciones_anomalas >= 3
    OR dispositivos_utilizados >= 3
    OR max_clientes_por_dispositivo >= 3
ORDER BY operaciones_anomalas DESC, operaciones_rapidas DESC, operaciones_grandes DESC
LIMIT 50;


-- ============================================================
-- 2. SEÑALES A NIVEL TRANSACCIÓN
-- Permite identificar operaciones con velocity, monto elevado,
-- anomalía estadística y/o dispositivo compartido.
-- ============================================================

WITH operaciones AS (
    SELECT
        t.transaccion_id,
        t.cliente_id,
        t.dispositivo_id,
        t.fecha_hora,
        t.monto,
        LAG(t.fecha_hora) OVER (
            PARTITION BY t.cliente_id
            ORDER BY t.fecha_hora, t.transaccion_id
        ) AS transaccion_anterior
    FROM transacciones t
),
estadisticas AS (
    SELECT
        cliente_id,
        AVG(monto) AS monto_promedio_cliente,
        STDDEV(monto) AS desviacion_cliente
    FROM transacciones
    GROUP BY cliente_id
),
dispositivos_compartidos AS (
    SELECT
        dispositivo_id,
        COUNT(DISTINCT cliente_id) AS clientes_distintos
    FROM transacciones
    WHERE dispositivo_id IS NOT NULL
    GROUP BY dispositivo_id
)
SELECT
    o.transaccion_id,
    o.cliente_id,
    o.dispositivo_id,
    o.fecha_hora,
    o.monto,
    TIMESTAMPDIFF(
        MINUTE,
        o.transaccion_anterior,
        o.fecha_hora
    ) AS minutos_desde_anterior,
    CASE
        WHEN s.desviacion_cliente > 0
        THEN (o.monto - s.monto_promedio_cliente) / s.desviacion_cliente
        ELSE NULL
    END AS z_score,
    COALESCE(dc.clientes_distintos, 0) AS clientes_distintos,
    CASE
        WHEN TIMESTAMPDIFF(MINUTE, o.transaccion_anterior, o.fecha_hora) <= 10
        THEN 1 ELSE 0
    END AS alerta_velocity,
    CASE
        WHEN o.monto >= 100000 THEN 1 ELSE 0
    END AS alerta_monto,
    CASE
        WHEN s.desviacion_cliente > 0
         AND o.monto > s.monto_promedio_cliente + (2 * s.desviacion_cliente)
        THEN 1 ELSE 0
    END AS alerta_anomalia,
    CASE
        WHEN COALESCE(dc.clientes_distintos, 0) >= 2
        THEN 1 ELSE 0
    END AS alerta_dispositivo_compartido
FROM operaciones o
LEFT JOIN estadisticas s ON o.cliente_id = s.cliente_id
LEFT JOIN dispositivos_compartidos dc ON o.dispositivo_id = dc.dispositivo_id
ORDER BY o.fecha_hora;


-- ============================================================
-- 3. VENTANA DE 10 MINUTOS
-- IMPORTANTE: RANGE con intervalo temporal en MySQL requiere un
-- único ORDER BY temporal. Por eso se utiliza únicamente fecha_hora.
-- ============================================================

WITH operaciones AS (
    SELECT
        t.transaccion_id,
        t.cliente_id,
        t.dispositivo_id,
        t.fecha_hora,
        t.monto,
        COUNT(*) OVER (
            PARTITION BY t.cliente_id
            ORDER BY t.fecha_hora
            RANGE BETWEEN INTERVAL 10 MINUTE PRECEDING
            AND CURRENT ROW
        ) AS operaciones_10_minutos,
        SUM(t.monto) OVER (
            PARTITION BY t.cliente_id
            ORDER BY t.fecha_hora
            RANGE BETWEEN INTERVAL 10 MINUTE PRECEDING
            AND CURRENT ROW
        ) AS monto_10_minutos
    FROM transacciones t
)
SELECT *
FROM operaciones
WHERE operaciones_10_minutos >= 5
ORDER BY operaciones_10_minutos DESC, monto_10_minutos DESC;


-- ============================================================
-- 4. BURSTS / OPERACIONES EXACTAMENTE SIMULTÁNEAS
-- Umbral: 5 o más operaciones del mismo cliente en el mismo
-- timestamp.
-- ============================================================

SELECT
    cliente_id,
    fecha_hora,
    COUNT(*) AS operaciones_simultaneas,
    ROUND(SUM(monto), 2) AS monto_simultaneo
FROM transacciones
GROUP BY cliente_id, fecha_hora
HAVING COUNT(*) >= 5
ORDER BY operaciones_simultaneas DESC, monto_simultaneo DESC
LIMIT 50;


-- ============================================================
-- 5. ESTADÍSTICAS GLOBALES DE BURSTS
-- ============================================================

SELECT
    COUNT(*) AS bursts_5_mas,
    MAX(operaciones_simultaneas) AS max_operaciones_simultaneas,
    AVG(operaciones_simultaneas) AS promedio_operaciones_simultaneas,
    MAX(monto_simultaneo) AS max_monto_simultaneo,
    AVG(monto_simultaneo) AS promedio_monto_simultaneo
FROM (
    SELECT
        cliente_id,
        fecha_hora,
        COUNT(*) AS operaciones_simultaneas,
        SUM(monto) AS monto_simultaneo
    FROM transacciones
    GROUP BY cliente_id, fecha_hora
    HAVING COUNT(*) >= 5
) bursts;


-- ============================================================
-- 6. DISTRIBUCIÓN DE BURSTS POR MAGNITUD
-- ============================================================

SELECT
    CASE
        WHEN operaciones_simultaneas BETWEEN 5 AND 9 THEN '5-9'
        WHEN operaciones_simultaneas BETWEEN 10 AND 19 THEN '10-19'
        WHEN operaciones_simultaneas BETWEEN 20 AND 49 THEN '20-49'
        WHEN operaciones_simultaneas BETWEEN 50 AND 99 THEN '50-99'
        WHEN operaciones_simultaneas BETWEEN 100 AND 149 THEN '100-149'
        WHEN operaciones_simultaneas BETWEEN 150 AND 199 THEN '150-199'
        ELSE '200+'
    END AS rango_burst,
    COUNT(*) AS cantidad_bursts
FROM (
    SELECT
        cliente_id,
        fecha_hora,
        COUNT(*) AS operaciones_simultaneas
    FROM transacciones
    GROUP BY cliente_id, fecha_hora
    HAVING COUNT(*) >= 5
) bursts
GROUP BY rango_burst
ORDER BY MIN(operaciones_simultaneas);


-- ============================================================
-- 7. RISK SCORE FINAL - VIEW DEFINITIVA
-- Esta es la consulta principal del proyecto.
-- ============================================================

CREATE OR REPLACE VIEW vw_fraud_risk_score AS

WITH operaciones AS (
    SELECT
        t.transaccion_id,
        t.cliente_id,
        t.dispositivo_id,
        t.fecha_hora,
        t.monto,
        t.estado_transaccion,
        LAG(t.fecha_hora) OVER (
            PARTITION BY t.cliente_id
            ORDER BY t.fecha_hora, t.transaccion_id
        ) AS transaccion_anterior
    FROM transacciones t
),
indicadores AS (
    SELECT
        transaccion_id,
        cliente_id,
        dispositivo_id,
        fecha_hora,
        monto,
        estado_transaccion,
        CASE
            WHEN transaccion_anterior IS NOT NULL
            THEN TIMESTAMPDIFF(SECOND, transaccion_anterior, fecha_hora)
            ELSE NULL
        END AS segundos_desde_anterior
    FROM operaciones
),
estadisticas_aprobadas AS (
    SELECT
        cliente_id,
        AVG(monto) AS monto_promedio_cliente,
        STDDEV(monto) AS desviacion_cliente
    FROM transacciones
    WHERE estado_transaccion = 'aprobada'
    GROUP BY cliente_id
),
dispositivos_compartidos AS (
    SELECT
        dispositivo_id,
        COUNT(DISTINCT cliente_id) AS clientes_distintos
    FROM transacciones
    WHERE dispositivo_id IS NOT NULL
    GROUP BY dispositivo_id
),
bursts AS (
    SELECT
        cliente_id,
        fecha_hora,
        COUNT(*) AS operaciones_simultaneas,
        SUM(monto) AS monto_simultaneo
    FROM transacciones
    GROUP BY cliente_id, fecha_hora
    HAVING COUNT(*) >= 5
),
bursts_cliente AS (
    SELECT
        cliente_id,
        COUNT(*) AS bursts_5_mas,
        MAX(operaciones_simultaneas) AS operaciones_simultaneas_maximas,
        MAX(monto_simultaneo) AS monto_maximo_simultaneo
    FROM bursts
    GROUP BY cliente_id
),
senales AS (
    SELECT
        i.cliente_id,
        COUNT(*) AS operaciones_totales,
        SUM(CASE WHEN i.estado_transaccion = 'aprobada' THEN 1 ELSE 0 END) AS operaciones_aprobadas,
        SUM(CASE WHEN i.segundos_desde_anterior <= 600 THEN 1 ELSE 0 END) AS operaciones_rapidas,
        SUM(CASE WHEN i.estado_transaccion = 'aprobada' AND i.monto >= 100000 THEN 1 ELSE 0 END) AS operaciones_grandes,
        SUM(CASE WHEN i.estado_transaccion = 'aprobada' AND i.monto >= 100000 THEN i.monto ELSE 0 END) AS monto_operaciones_grandes,
        COUNT(DISTINCT i.dispositivo_id) AS dispositivos_utilizados,
        COALESCE(MAX(dc.clientes_distintos), 0) AS max_clientes_por_dispositivo,
        SUM(
            CASE
                WHEN i.estado_transaccion = 'aprobada'
                 AND ea.desviacion_cliente > 0
                 AND i.monto > ea.monto_promedio_cliente + (2 * ea.desviacion_cliente)
                THEN 1 ELSE 0
            END
        ) AS operaciones_anomalas,
        MAX(
            CASE
                WHEN i.estado_transaccion = 'aprobada'
                 AND ea.desviacion_cliente > 0
                THEN (i.monto - ea.monto_promedio_cliente) / ea.desviacion_cliente
                ELSE NULL
            END
        ) AS z_score_maximo
    FROM indicadores i
    LEFT JOIN estadisticas_aprobadas ea ON i.cliente_id = ea.cliente_id
    LEFT JOIN dispositivos_compartidos dc ON i.dispositivo_id = dc.dispositivo_id
    GROUP BY i.cliente_id
),
scores AS (
    SELECT
        s.*,
        CASE WHEN operaciones_rapidas >= 100 THEN 3 WHEN operaciones_rapidas >= 50 THEN 2 WHEN operaciones_rapidas >= 10 THEN 1 ELSE 0 END AS score_velocity,
        CASE WHEN operaciones_grandes >= 20 THEN 3 WHEN operaciones_grandes >= 10 THEN 2 WHEN operaciones_grandes >= 3 THEN 1 ELSE 0 END AS score_montos,
        CASE WHEN operaciones_anomalas >= 12 THEN 3 WHEN operaciones_anomalas >= 8 THEN 2 WHEN operaciones_anomalas >= 3 THEN 1 ELSE 0 END AS score_anomalias,
        CASE WHEN z_score_maximo > 8 THEN 3 WHEN z_score_maximo > 6 THEN 2 WHEN z_score_maximo > 4 THEN 1 ELSE 0 END AS score_zscore,
        CASE WHEN dispositivos_utilizados >= 4 THEN 3 WHEN dispositivos_utilizados >= 3 THEN 2 WHEN dispositivos_utilizados >= 2 THEN 1 ELSE 0 END AS score_dispositivos,
        CASE WHEN max_clientes_por_dispositivo >= 4 THEN 3 WHEN max_clientes_por_dispositivo >= 3 THEN 2 WHEN max_clientes_por_dispositivo >= 2 THEN 1 ELSE 0 END AS score_compartidos
    FROM senales s
),
score_final AS (
    SELECT *,
        (score_velocity + score_montos + score_anomalias + score_zscore + score_dispositivos + score_compartidos) AS risk_score
    FROM scores
)
SELECT
    sf.cliente_id,
    sf.operaciones_totales,
    sf.operaciones_aprobadas,
    sf.operaciones_rapidas,
    sf.operaciones_grandes,
    ROUND(sf.monto_operaciones_grandes, 2) AS monto_operaciones_grandes,
    sf.operaciones_anomalas,
    ROUND(sf.z_score_maximo, 2) AS z_score_maximo,
    sf.dispositivos_utilizados,
    sf.max_clientes_por_dispositivo,
    COALESCE(bc.bursts_5_mas, 0) AS bursts_5_mas,
    COALESCE(bc.operaciones_simultaneas_maximas, 0) AS operaciones_simultaneas_maximas,
    ROUND(COALESCE(bc.monto_maximo_simultaneo, 0), 2) AS monto_maximo_simultaneo,
    sf.score_velocity,
    sf.score_montos,
    sf.score_anomalias,
    sf.score_zscore,
    sf.score_dispositivos,
    sf.score_compartidos,
    sf.risk_score,
    CASE
        WHEN sf.risk_score >= 13 THEN 'CRITICO'
        WHEN sf.risk_score >= 9 THEN 'ALTO'
        WHEN sf.risk_score >= 5 THEN 'MEDIO'
        ELSE 'BAJO'
    END AS nivel_riesgo
FROM score_final sf
LEFT JOIN bursts_cliente bc ON sf.cliente_id = bc.cliente_id;


-- ============================================================
-- 8. CONSULTAR EL RESULTADO FINAL
-- ============================================================

SELECT *
FROM vw_fraud_risk_score
ORDER BY risk_score DESC;


-- ============================================================
-- 9. DISTRIBUCIÓN FINAL DE RIESGO
-- Resultado validado en el proyecto:
-- BAJO  = 3.414 (78,54%)
-- MEDIO =   814 (18,73%)
-- ALTO  =   118 ( 2,71%)
-- CRITICO =   1 ( 0,02%)
-- TOTAL = 4.347 (100%)
-- ============================================================

SELECT
    nivel_riesgo,
    COUNT(*) AS cantidad_clientes,
    ROUND(
        COUNT(*) * 100.0 /
        SUM(COUNT(*)) OVER (),
        2
    ) AS porcentaje
FROM vw_fraud_risk_score
GROUP BY nivel_riesgo
ORDER BY
    CASE nivel_riesgo
        WHEN 'BAJO' THEN 1
        WHEN 'MEDIO' THEN 2
        WHEN 'ALTO' THEN 3
        WHEN 'CRITICO' THEN 4
    END;


-- ============================================================
-- 10. TOP DE CLIENTES PARA INVESTIGACIÓN
-- ============================================================

SELECT
    cliente_id,
    risk_score,
    nivel_riesgo,
    operaciones_rapidas,
    operaciones_grandes,
    monto_operaciones_grandes,
    operaciones_anomalas,
    z_score_maximo,
    dispositivos_utilizados,
    max_clientes_por_dispositivo,
    bursts_5_mas,
    operaciones_simultaneas_maximas,
    monto_maximo_simultaneo
FROM vw_fraud_risk_score
WHERE nivel_riesgo IN ('CRITICO', 'ALTO')
ORDER BY risk_score DESC,
         operaciones_anomalas DESC,
         operaciones_rapidas DESC;


-- ============================================================
-- NOTAS METODOLÓGICAS
-- ============================================================
-- 1. Velocity y bursts utilizan las transacciones del dataset.
-- 2. Operaciones grandes y anomalías monetarias utilizan operaciones
--    aprobadas para medir exposición y comportamiento efectivo.
-- 3. El Risk Score es heurístico y no está calibrado como una
--    probabilidad de fraude.
-- 4. Las señales representan indicadores de riesgo, no fraude confirmado.
-- 5. Bursts no se agregan como componente adicional del score para
--    evitar doble conteo con velocity.
