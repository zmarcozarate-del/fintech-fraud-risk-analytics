# Fintech Fraud & Risk Analytics

## 📊 Overview

This project simulates a **Fraud & Risk Analytics environment for an Argentine fintech**, using synthetic transactional and behavioral data to identify risk signals, calculate a rule-based Risk Score, and prioritize customers for further investigation.

The project combines **MySQL, SQL and Power BI** to transform structured transactional data into actionable risk indicators and an interactive risk monitoring dashboard.

> **Important:** This is a portfolio project based entirely on synthetic data. No real customers, financial institutions, transactions or confidential information are involved.

---

## 🎯 Project Objectives

* Analyze transactional behavior and identify potential risk signals.
* Detect unusual transaction patterns using SQL.
* Build a rule-based customer **Risk Score**.
* Segment customers according to risk level.
* Identify customers that may require priority review.
* Build an interactive Power BI dashboard for risk monitoring and investigation support.
* Demonstrate the application of data analytics techniques to **Fraud, AML and Risk Management** scenarios.

---

## 🗂️ Data Source & Dataset

The dataset was **synthetically generated specifically for this project** to simulate the type of transactional and customer data that could be found in an Argentine fintech environment.

The data does not originate from a real financial institution and does not contain real customer information.

The synthetic dataset was designed to reproduce realistic relationships between customers, accounts, cards, devices, merchants, transactions, transfers and login activity, allowing the project to demonstrate data modeling and risk-analysis techniques without exposing sensitive or confidential information.

The analysis covers the period:

**July 2025 – June 2026**

### Dataset scope

* **Customers:** 5,000
* **Provinces:** 24
* **Transactions:** 201,074
* **Purchases:** 184,214
* **Service payments:** 16,860
* **Approved transfers:** 57,230
* **Rejected transfers:** 2,332
* **Reversed transfers:** 1,189

The complete underlying dataset is not included in this repository. Selected data structures, analytical queries and dashboard outputs are provided to demonstrate the methodology and results while keeping the repository lightweight.

---

## 🗄️ Data Model

The simulated MySQL database `fintech_fraud` contains 11 relational tables:

* `provincias`
* `locations`
* `clientes`
* `cuentas`
* `tarjetas`
* `dispositivos`
* `comercios`
* `beneficiaries`
* `login_events`
* `transacciones`
* `transferencias`

The relational structure was designed to reproduce a simplified fintech data environment and allow analysis across customers, accounts, devices, transactions, transfers and behavioral activity.

---

## 🔎 Risk Detection Methodology

The analysis combines several behavioral signals.

### 1. Transaction Velocity

Transactions were analyzed using SQL window functions, including `LAG()`, to identify operations performed within short time intervals.

Transactions occurring within **600 seconds** of a previous transaction were considered rapid operations.

### 2. Large Transactions

Approved transactions with amounts of **ARS 100,000 or more** were analyzed to identify customers with repeated high-value activity.

The analysis includes:

* Number of large transactions.
* Total amount of large transactions.
* Risk contribution based on transaction frequency.

### 3. Amount Anomalies

Customer transaction amounts were compared against their historical behavior using:

* Mean transaction amount.
* Standard deviation.
* Z-score.

Transactions significantly above the customer's normal range were classified as potential amount anomalies.

### 4. Device Usage

Device behavior was analyzed through:

* Number of devices used by each customer.
* Number of customers associated with the same device.
* Potential device-sharing patterns.

### 5. Transaction Bursts

Groups of transactions occurring at the same date and time were identified.

A **burst** was defined as a customer having five or more transactions at the same timestamp.

This signal was analyzed separately and was not added as an additional Risk Score component in order to avoid overlapping its effect with transaction velocity.

---

## 🧮 Risk Score

A rule-based **Risk Score** was created by combining the different behavioral signals.

The maximum score is **18 points**.

| Score | Risk Level |
| ----: | ---------- |
|   0–4 | LOW        |
|   5–8 | MEDIUM     |
|  9–12 | HIGH       |
| 13–18 | CRITICAL   |

The final SQL view is:

```sql
vw_fraud_risk_score
```

The view contains **4,347 customers with evaluable transaction activity**.

The remaining 653 customers belong to the general customer population but do not have transactions included in the risk evaluation.

> The Risk Score is a heuristic prioritization mechanism. It does not represent a statistical probability of fraud or a confirmed fraud classification.

---

## 📈 Risk Distribution

| Risk Level | Customers |        % |
| ---------- | --------: | -------: |
| LOW        |     3,414 |   78.54% |
| MEDIUM     |       814 |   18.73% |
| HIGH       |       118 |    2.71% |
| CRITICAL   |         1 |    0.02% |
| **Total**  | **4,347** | **100%** |

---

## 🚨 Investigation Prioritization

The customer with the highest Risk Score was:

**Customer ID: 3006**

Key indicators:

* 217 total transactions
* 191 approved transactions
* 192 rapid transactions
* 22 large transactions
* ARS 4,638,640.81 in large transactions
* 10 anomalous transactions
* 4 devices used
* Up to 4 customers associated with the same device
* 2 transaction bursts
* Maximum of 142 simultaneous transactions
* Risk Score: **15**
* Risk Level: **CRITICAL**

This classification does **not** mean that the customer committed fraud. It identifies a customer whose combination of behavioral signals makes the case suitable for **priority review and investigation**.

---

# 📊 Power BI Dashboard
![Executive Risk Overview](./images/dash%20pag%201.png)

![Fraud & Risk Detection](./images/dash%20pag%202.png)

![Investigation & Case Prioritization](./images/dash%20pag%203.png)
The Power BI dashboard is organized into three pages.

### 1. Executive Risk Overview

Provides a high-level view of the risk environment, including:

* Total customers
* Evaluated customers
* Non-evaluated customers
* Total transactions
* Customer distribution by risk level
* Transactions by risk level
* Top customers by Risk Score

### 2. Fraud & Risk Detection

Focuses on the main behavioral signals:

* Rapid transactions
* Large transactions
* Amount anomalies
* High-risk customers
* Critical-risk customers
* Total amount of large transactions
* Risk Score distribution
* Rapid transactions by risk level
* Device usage by risk level
* Anomalous transactions by risk level
* Shared-device indicators

### 3. Investigation & Case Prioritization

Designed to support analyst review and case prioritization.

The page includes:

* Customer ID
* Risk level
* Risk Score
* Rapid transactions
* Large transactions
* Anomalous transactions
* Maximum Z-score
* Devices used
* Maximum customers per device
* Transaction bursts
* Maximum simultaneous transactions
* Maximum simultaneous transaction amount
* Risk-level filters
* Risk Score filters

The investigation table is sorted by Risk Score in descending order to surface higher-priority cases first.

---

## 📐 Power BI Measures

A dedicated `Medidas` table was created to centralize the main DAX measures.

Examples include:

```text
Total Clientes
Clientes Evaluados
Clientes No Evaluados
Total Operaciones
Operaciones Aprobadas
Operaciones Rápidas
Operaciones Grandes
Operaciones Anómalas
Monto Operaciones Grandes
Clientes Alto Riesgo
Clientes Críticos
Clientes Riesgo Medio
Clientes Bajo Riesgo
```

---

## 🛠️ Technologies

* **MySQL**
* **SQL**
* **Power BI**
* **DAX**
* **CSV**
* Relational data modeling
* SQL window functions
* Statistical anomaly detection
* Rule-based risk scoring
* Data visualization

---

## 💡 Key SQL Techniques

The project applies several SQL techniques commonly used in data analytics and risk environments:

* `JOIN`
* `GROUP BY`
* `CASE`
* Aggregate functions
* Window functions
* `LAG()`
* Conditional aggregation
* Standard deviation
* Z-score calculations
* Common Table Expressions (CTEs)
* SQL Views

---

## ⚠️ Limitations

This project is designed for portfolio and educational purposes.

* The dataset is entirely synthetic.
* No real customer or financial information is used.
* There is no original confirmed-fraud label.
* There is no original fraud-alert table.
* Risk rules were designed specifically for this analytical exercise.
* The Risk Score is not a machine-learning model.
* The Risk Score does not represent the probability of fraud.
* High- and critical-risk customers should be interpreted as **priority cases for review**, not confirmed fraudulent customers.
* The complete synthetic dataset is not included in the repository; the project focuses on the analytical methodology, SQL logic and Power BI outputs.

---

## 🎯 Professional Focus

This project demonstrates how data analytics can support:

**Fraud Analytics · AML · Transaction Monitoring · Operational Risk · Compliance Analytics · Risk-Based Customer Review · Data Quality · Investigation Prioritization**

The objective is to bridge **legal/compliance domain knowledge with SQL, data analytics and business intelligence**, creating practical analytical solutions for financial services and fintech environments.
