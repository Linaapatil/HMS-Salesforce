@IsTest(SeeAllData=false)
private class DailyAppointmentReminderTest {
    @TestSetup
    static void setup() {
        Doctor__c doctor = TestDataFactory.createDoctor();
        List<Patient__c> patients = TestDataFactory.createPatients(3);
        Date tomorrow = Date.today().addDays(1);

        List<Appointment__c> appointments = new List<Appointment__c>{
            TestDataFactory.buildAppointment(doctor.Id, patients[0].Id, tomorrow, '09:00 AM'),
            TestDataFactory.buildAppointment(doctor.Id, patients[1].Id, tomorrow, '10:00 AM'),
            TestDataFactory.buildAppointment(doctor.Id, patients[2].Id, tomorrow.addDays(3), '10:00 AM')
        };
        appointments[1].Status__c = 'Cancelled';
        insert appointments;
    }

    @IsTest
    static void startOnlySelectsTomorrowsActiveAppointments() {
        DailyAppointmentReminder reminder = new DailyAppointmentReminder();

        Test.startTest();
        Database.QueryLocatorIterator iterator = reminder.start(null).iterator();
        Test.stopTest();

        Integer count = 0;
        while (iterator.hasNext()) {
            iterator.next();
            count++;
        }
        Assert.areEqual(1, count, 'Only tomorrow, non-cancelled, with email');
    }

    @IsTest
    static void batchSendsReminders() {
        Test.startTest();
        Database.executeBatch(new DailyAppointmentReminder(), 200);
        Test.stopTest();

        Assert.areEqual('Completed', [SELECT Status FROM AsyncApexJob WHERE JobType = 'BatchApex' LIMIT 1].Status);
    }

    @IsTest
    static void executeQueuesEmails() {
        List<Appointment__c> appointments = [SELECT Id, Name, Patient_Email__c, Appointment_Date__c, Slot__c FROM Appointment__c WHERE Status__c != 'Cancelled'];

        Test.startTest();
        new DailyAppointmentReminder().execute((Database.BatchableContext) null, appointments);
        Test.stopTest();

        Assert.areEqual(appointments.size(), EmailService.emailsQueued);
    }

    @IsTest
    static void schedulesDailyAt6am() {
        Test.startTest();
        Id jobId = DailyAppointmentReminder.scheduleDaily('Test ' + DailyAppointmentReminder.JOB_NAME);
        new DailyAppointmentReminder().execute((SchedulableContext) null);
        Test.stopTest();

        Assert.areEqual(DailyAppointmentReminder.CRON_6AM_DAILY, [SELECT CronExpression FROM CronTrigger WHERE Id = :jobId].CronExpression);
    }
}
