// Schedules the HMS async jobs (run once per org):
//   - Daily Appointment Reminder (Schedulable + Batch) every day at 6 AM
//   - Monthly Billing Report (Batch) on the 1st of every month at 7 AM
// Run with:  sf apex run -o MedCare -f scripts/apex/scheduleJobs.apex
Set<String> existing = new Set<String>();
for (CronTrigger job : [SELECT CronJobDetail.Name FROM CronTrigger]) {
    existing.add(job.CronJobDetail.Name);
}
if (!existing.contains(DailyAppointmentReminder.JOB_NAME)) {
    System.debug('Scheduled: ' + DailyAppointmentReminder.scheduleDaily());
}
if (!existing.contains(MonthlyBillingReport.JOB_NAME)) {
    System.debug('Scheduled: ' + MonthlyBillingReport.scheduleMonthly());
}
