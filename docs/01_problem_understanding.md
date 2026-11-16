# CP1 – Problem Understanding

**Project:** Google Pay (UPI) Digital Payments Database  
**Team:** T0129

This document explains the main problems mentioned in our project and the queries related to them. It also mentions which teams or users are affected and what type of workload each problem involves.

| Problem | What is the problem? | Who is affected? | Primary workload type | Related queries |
|---|---|---|---|---|
| P1 | Users should be able to check their transaction history, active UPI IDs and linked bank accounts without much delay. | Users, payer and payee | Customer-facing / real-time | R01, R02, R22 |
| P2 | The system should check how much a user has spent through UPI in a day before processing a payment. | Users and payment team | Customer-facing / real-time | R03, W01 |
| P3 | Operations must find payments stuck in pending status and process bank responses promptly. | Operations and bank partners | Customer-facing / real-time | R04, W02 |
| P4 | Merchants need collection summaries, daily settlement amounts, and a list of merchants without payments. | Merchants and settlement team | Reporting / analytics | R05, R06, R13 |
| P5 | Fraud and risk teams need to spot mule accounts, repeated payments and unusually high merchant refund rates. | Fraud and risk team, users and merchants | Customer-facing / real-time | R08, R09, R17 |
| P6 | Users need to view rewards and bills; scheduled jobs also expire rewards and mark unpaid bills overdue. | Users and rewards/bills team | Reporting / analytics | R10, R11, R12, W03, W04, W05 |
| P7 | Support needs fast dispute queues and payment lookups; compliance needs KYC-risk reports. | Compliance and customer support teams | Customer-facing / real-time | R16, R18, R23, R24 |
| P8 | Bank partners and business teams need payment-failure, response-time, success-rate and trend reports. | Bank partners and analytics team | Reporting / analytics | R07, R14, R15, R19, R20, R21, R25 |

## Assumptions

- The query IDs are mapped according to the problem statements given in the README file.
- Real-time queries are the ones needed while a user is using the app or making a payment.
- Reporting queries are mainly used to study payment data, trends and performance.
- The workload column uses one primary category per problem as requested. Some listed queries have secondary uses: R05 is an interactive merchant view, R10/R12 are user-facing reads, R17 and R18 are analytics reports, and W03–W05 are batch writes.
- P5 is classified as customer-facing / real-time because the problem statement calls for near-real-time risk checks; R17 is the reporting query in that group.
- The dates, amounts and user IDs in the SQL file are examples used for the workload and may not represent fixed business rules.
