@IsTest(SeeAllData=false)
private class MonthlyBillingReportTest {
    @TestSetup
    static void setup() {
        Department__c cardiology = TestDataFactory.createDepartment('Cardiology');
        Doctor__c doctor = TestDataFactory.createDoctor(cardiology.Id);
        Patient__c patient = TestDataFactory.createPatient();
        Procedure__c procedure = TestDataFactory.createProcedure(10000);

        List<Appointment__c> appointments = new List<Appointment__c>{
            TestDataFactory.buildAppointment(doctor.Id, patient.Id, Date.today().addDays(1), '10:00 AM'),
            TestDataFactory.buildAppointment(doctor.Id, patient.Id, Date.today().addDays(1), '11:00 AM')
        };
        insert appointments;

        insert new List<Billing__c>{
            TestDataFactory.buildBilling(patient.Id, procedure.Id, appointments[0].Id),
            TestDataFactory.buildBilling(patient.Id, procedure.Id, appointments[1].Id)
        };
    }

    @IsTest
    static void batchRunsForCurrentMonth() {
        Test.startTest();
        Database.executeBatch(new MonthlyBillingReport(Date.today()), 200);
        Test.stopTest();

        AsyncApexJob job = [SELECT Status, NumberOfErrors FROM AsyncApexJob WHERE JobType = 'BatchApex' LIMIT 1];
        Assert.areEqual('Completed', job.Status);
        Assert.areEqual(0, job.NumberOfErrors);
    }

    @IsTest
    static void executeAndFinishBuildReport() {
        MonthlyBillingReport report = new MonthlyBillingReport(Date.today());
        List<Billing__c> bills = [SELECT Id, Amount_Due__c, Insurance_Amount__c, Department_Name__c FROM Billing__c];

        Test.startTest();
        // Two execute() calls = two chunks; totals accumulate because the batch is Database.Stateful.
        report.execute(null, new List<Billing__c>{ bills[0] });
        report.execute(null, new List<Billing__c>{ bills[1] });
        String body = report.buildReportBody();
        report.finish(null);
        Test.stopTest();

        Assert.areEqual(2, report.billingCount);
        Assert.areEqual(14400, report.totalAmount, '2 x (10000 - 10% - 20% insurance)');
        Assert.areEqual(14400, report.amountByDepartment.get('Cardiology'));
        Assert.isTrue(body.contains('Total Bills: 2'));
        Assert.isTrue(body.contains('Cardiology: 14400.00'));
        Assert.isTrue(EmailService.emailsQueued > 0, 'Report email queued');
    }

    @IsTest
    static void previousMonthHasNoBills() {
        Test.startTest();
        Database.executeBatch(new MonthlyBillingReport(), 200);
        Test.stopTest();

        Assert.areEqual('Completed', [SELECT Status FROM AsyncApexJob WHERE JobType = 'BatchApex' LIMIT 1].Status);
    }

    @IsTest
    static void schedulesOnFirstOfMonth() {
        Test.startTest();
        Id jobId = MonthlyBillingReport.scheduleMonthly('Test ' + MonthlyBillingReport.JOB_NAME);
        Test.stopTest();

        CronTrigger cron = [SELECT CronExpression FROM CronTrigger WHERE Id = :jobId];
        Assert.areEqual(MonthlyBillingReport.CRON_FIRST_OF_MONTH, cron.CronExpression);
    }

    @IsTest
    static void schedulableStartsBatch() {
        Test.startTest();
        new MonthlyBillingReport().execute((SchedulableContext) null);
        Test.stopTest();

        Assert.areEqual(1, [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'BatchApex']);
    }
}
