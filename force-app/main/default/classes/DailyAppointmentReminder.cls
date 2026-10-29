/**
 * Schedulable + Batch Apex: every day at 6 AM, emails a reminder to every patient
 * with a (non-cancelled) appointment tomorrow.
 *
 * Schedule it once with:  DailyAppointmentReminder.scheduleDaily();
 */
public with sharing class DailyAppointmentReminder implements Schedulable, Database.Batchable<SObject> {
    public static final String JOB_NAME = 'HMS Daily Appointment Reminder - 6 AM';
    public static final String CRON_6AM_DAILY = '0 0 6 * * ?';

    public static Id scheduleDaily() {
        return scheduleDaily(JOB_NAME);
    }

    /** Job names are unique per org, so tests pass their own name. */
    public static Id scheduleDaily(String jobName) {
        return System.schedule(jobName, CRON_6AM_DAILY, new DailyAppointmentReminder());
    }

    public void execute(SchedulableContext context) {
        Database.executeBatch(new DailyAppointmentReminder(), 200);
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        Date tomorrow = Date.today().addDays(1);
        return Database.getQueryLocator(
            [
                SELECT Id, Name, Patient_Email__c, Appointment_Date__c, Slot__c
                FROM Appointment__c
                WHERE Appointment_Date__c = :tomorrow AND Status__c != 'Cancelled' AND Patient_Email__c != NULL
            ]
        );
    }

    public void execute(Database.BatchableContext context, List<Appointment__c> appointments) {
        EmailService.sendReminderEmails(appointments);
    }

    public void finish(Database.BatchableContext context) {
        System.debug(LoggingLevel.INFO, 'Daily appointment reminders sent for job ' + context.getJobId());
    }
}
