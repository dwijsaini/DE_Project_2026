# CP1 – Problem Understanding

**Project:** Google Pay (UPI) Digital Payments Database  
**Team:** T0129

This document explains the main problems mentioned in our project and the queries related to them. It also mentions which teams or users are affected and what type of workload each problem involves.

| Problem | What is the problem? | Who is affected? | Workload type | Related queries |
|---|---|---|---|---|
| P1 | Users should be able to check their transaction history, active UPI IDs and linked bank accounts without much delay. | Users, payer and payee | Customer-facing / real-time | R01, R02, R22 |
| P2 | The system should check how much a user has spent through UPI in a day before processing a payment. | Users and payment team | Customer-facing / real-time | R03, W01 |
| P3 | Payments that are stuck in pending status should be identified, and bank responses should be handled properly. | Operations and bank partners | Operational / real-time | R04, W02 |
| P4 | Merchants should be able to check received payments, daily settlement amounts and find out if they have not received any payments. | Merchants and settlement team | Mixed: interactive and reporting | R05, R06, R13 |
| P5 | The system should help identify unusual payment activity, repeated payments and merchants with high refund rates. | Fraud and risk team, users and merchants | Risk monitoring / analytics | R08, R09, R17 |
| P6 | Users should be able to check their rewards and bills. The system should also update expired rewards and overdue bills when required. | Users and rewards/bills team | Mixed: user-facing and batch processing | R10, R11, R12, W03, W04, W05 |
| P7 | The system should help check KYC-related risks and old disputes. It should also support transaction searches using UPI reference numbers. | Compliance and customer support teams | Mixed: reporting and operational | R16, R18, R23, R24 |
| P8 | Bank partners and business teams should be able to track failed payments, response time, success rates and payment trends. | Bank partners and analytics team | Mainly reporting / analytics | R07, R14, R15, R19, R20, R21, R25 |

## Assumptions

- The query IDs are mapped according to the problem statements given in the README file.
- Real-time queries are the ones needed while a user is using the app or making a payment.
- Reporting queries are mainly used to study payment data, trends and performance.
- Some problems include both types of work, so they are marked as mixed.
- P5 mentions near-real-time risk checks, but the checkpoint document places its related queries under reports/risk/analytics. This needs to be confirmed with the team.
- The dates, amounts and user IDs in the SQL file are examples used for the workload and may not represent fixed business rules.
