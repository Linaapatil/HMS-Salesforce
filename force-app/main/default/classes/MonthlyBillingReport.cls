/**
 * Batch Apex: runs on the 1st of every month, aggregates the previous month's billing
 * by department and emails the report to the Finance team (Custom Label HMS_Finance_Team_Email,
 * comma separated).
 *
 * Schedule it once with:  MonthlyBillingReport.scheduleMonthly();
 */
public with sharing class MonthlyBillingReport implements Database.Batchable<SObject>, Database.Stateful, Schedulable {
    public static final String JOB_NAME = 'HMS Monthly Billing Report - 1st of month';
    public static final String CRON_FIRST_OF_MONTH = '0 0 7 1 * ?';

    private final Date periodStart;
    private final Date periodEnd;

    // Stateful totals that survive across execute() chunks.
    public Integer billingCount = 0;
    public Decimal totalAmount = 0;
    public Decimal totalInsurance = 0;
    public Map<String, Decimal> amountByDepartment = new Map<String, Decimal>();

    /** Defaults to the previous calendar month. */
    public MonthlyBillingReport() {
        this(Date.today().toStartOfMonth().addMonths(-1));
    }

    public MonthlyBillingReport(Date anyDayInMonth) {
        periodStart = anyDayInMonth.toStartOfMonth();
        periodEnd = periodStart.addMonths(1);
    }

    public static Id scheduleMonthly() {
        return scheduleMonthly(JOB_NAME);
    }

    /** Job names are unique per org, so tests pass their own name. */
    public static Id scheduleMonthly(String jobName) {
        return System.schedule(jobName, CRON_FIRST_OF_MONTH, new MonthlyBillingReport());
    }

    public void execute(SchedulableContext context) {
        Database.executeBatch(new MonthlyBillingReport(), 200);
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        Datetime startTime = Datetime.newInstance(periodStart, Time.newInstance(0, 0, 0, 0));
        Datetime endTime = Datetime.newInstance(periodEnd, Time.newInstance(0, 0, 0, 0));
        return Database.getQueryLocator(
            [
                SELECT Id, Amount_Due__c, Insurance_Amount__c, Department_Name__c
                FROM Billing__c
                WHERE CreatedDate >= :startTime AND CreatedDate < :endTime
            ]
        );
    }

    public void execute(Database.BatchableContext context, List<Billing__c> bills) {
        for (Billing__c bill : bills) {
            Decimal amount = bill.Amount_Due__c == null ? 0 : bill.Amount_Due__c;
            String department = String.isBlank(bill.Department_Name__c) ? 'Unassigned' : bill.Department_Name__c;

            billingCount++;
            totalAmount += amount;
            totalInsurance += bill.Insurance_Amount__c == null ? 0 : bill.Insurance_Amount__c;
            amountByDepartment.put(department, (amountByDepartment.containsKey(department) ? amountByDepartment.get(department) : 0) + amount);
        }
    }

    public void finish(Database.BatchableContext context) {
        EmailService.sendEmail(getRecipients(), 'MedCare Monthly Billing Report - ' + periodLabel(), buildReportBody());
    }

    @TestVisible
    private String buildReportBody() {
        List<String> lines = new List<String>{
            'Monthly Billing Report: ' + periodLabel(),
            '',
            'Total Bills: ' + billingCount,
            'Total Amount Due: ' + totalAmount.setScale(2),
            'Total Insurance Covered: ' + totalInsurance.setScale(2),
            '',
            'Revenue by Department:'
        };

        List<String> departments = new List<String>(amountByDepartment.keySet());
        departments.sort();
        for (String department : departments) {
            lines.add('  - ' + department + ': ' + amountByDepartment.get(department).setScale(2));
        }
        return String.join(lines, '\n');
    }

    private String periodLabel() {
        return Datetime.newInstance(periodStart, Time.newInstance(0, 0, 0, 0)).format('MMMM yyyy');
    }

    private static List<String> getRecipients() {
        String configured = System.Label.HMS_Finance_Team_Email;
        List<String> recipients = String.isBlank(configured) ? new List<String>() : configured.split(',');
        recipients.add(UserInfo.getUserEmail());
        return recipients;
    }
}
