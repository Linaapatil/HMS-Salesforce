// Runs the async jobs immediately (useful for a demo).
Database.executeBatch(new DailyAppointmentReminder(), 200);
Database.executeBatch(new MonthlyBillingReport(Date.today()), 200);
