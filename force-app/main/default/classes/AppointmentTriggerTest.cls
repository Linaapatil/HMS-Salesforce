@IsTest(SeeAllData=false)
private class AppointmentTriggerTest {
    private static final Date TOMORROW = Date.today().addDays(1);

    @TestSetup
    static void setup() {
        Department__c department = TestDataFactory.createDepartment('Cardiology');
        TestDataFactory.createDoctor(department.Id);
        TestDataFactory.createPatients(2);
    }

    private static Doctor__c doctor() {
        return [SELECT Id, Active_Appointments__c FROM Doctor__c LIMIT 1];
    }

    private static List<Patient__c> patients() {
        return [SELECT Id, Email__c FROM Patient__c ORDER BY Full_Name__c];
    }

    @IsTest
    static void insertCreatesConfirmationTaskAndCopiesEmail() {
        Patient__c patient = patients()[0];

        Test.startTest();
        Appointment__c appointment = TestDataFactory.createAppointment(doctor().Id, patient.Id, TOMORROW, '09:00 AM');
        Test.stopTest();

        List<Task> tasks = [SELECT Subject, OwnerId FROM Task WHERE WhatId = :appointment.Id];
        Assert.areEqual(1, tasks.size(), 'One confirmation task per appointment');
        Assert.areEqual('Confirm appointment with patient', tasks[0].Subject);
        Assert.areEqual(UserInfo.getUserId(), tasks[0].OwnerId);

        Appointment__c saved = [SELECT Patient_Email__c FROM Appointment__c WHERE Id = :appointment.Id];
        Assert.areEqual(patient.Email__c, saved.Patient_Email__c);

        Patient__c updatedPatient = [SELECT Total_Appointments__c FROM Patient__c WHERE Id = :patient.Id];
        Assert.areEqual(1, updatedPatient.Total_Appointments__c, 'Apex roll-up counts appointments');
    }

    @IsTest
    static void pastDateRejected() {
        Test.startTest();
        Database.SaveResult result = Database.insert(
            TestDataFactory.buildAppointment(doctor().Id, patients()[0].Id, Date.today().addDays(-1), '09:00 AM'),
            false
        );
        Test.stopTest();

        Assert.isFalse(result.isSuccess());
        Assert.areEqual(AppointmentTriggerHandler.MSG_PAST_DATE, result.getErrors()[0].getMessage());
    }

    @IsTest
    static void missingDateRejected() {
        Test.startTest();
        Database.SaveResult result = Database.insert(TestDataFactory.buildAppointment(doctor().Id, patients()[0].Id, null, '09:00 AM'), false);
        Test.stopTest();

        Assert.isFalse(result.isSuccess());
        Assert.areEqual(AppointmentTriggerHandler.MSG_DATE_REQUIRED, result.getErrors()[0].getMessage());
    }

    @IsTest
    static void doubleBookingAgainstExistingRejected() {
        List<Patient__c> patients = patients();
        TestDataFactory.createAppointment(doctor().Id, patients[0].Id, TOMORROW, '10:00 AM');

        Test.startTest();
        Database.SaveResult result = Database.insert(TestDataFactory.buildAppointment(doctor().Id, patients[1].Id, TOMORROW, '10:00 AM'), false);
        Test.stopTest();

        Assert.isFalse(result.isSuccess());
        Assert.areEqual(AppointmentTriggerHandler.MSG_DOUBLE_BOOKED, result.getErrors()[0].getMessage());
    }

    @IsTest
    static void doubleBookingWithinSameBatchRejected() {
        List<Patient__c> patients = patients();
        List<Appointment__c> appointments = new List<Appointment__c>{
            TestDataFactory.buildAppointment(doctor().Id, patients[0].Id, TOMORROW, '11:00 AM'),
            TestDataFactory.buildAppointment(doctor().Id, patients[1].Id, TOMORROW, '11:00 AM')
        };

        Test.startTest();
        List<Database.SaveResult> results = Database.insert(appointments, false);
        Test.stopTest();

        Assert.isTrue(results[0].isSuccess());
        Assert.isFalse(results[1].isSuccess());
    }

    @IsTest
    static void cancelledSlotCanBeRebooked() {
        List<Patient__c> patients = patients();
        Appointment__c first = TestDataFactory.createAppointment(doctor().Id, patients[0].Id, TOMORROW, '02:00 PM');
        first.Status__c = 'Cancelled';
        update first;

        Test.startTest();
        Appointment__c second = TestDataFactory.createAppointment(doctor().Id, patients[1].Id, TOMORROW, '02:00 PM');
        Test.stopTest();

        Assert.isNotNull(second.Id);
    }

    @IsTest
    static void bulkInsertOf200() {
        Doctor__c doc = doctor();
        Id patientId = patients()[0].Id;
        List<Appointment__c> appointments = new List<Appointment__c>();

        // 200 appointments: 13 slots/day spread across 16 days.
        for (Integer i = 0; i < 200; i++) {
            Date day = TOMORROW.addDays(i / TestDataFactory.SLOTS.size());
            String slot = TestDataFactory.SLOTS[Math.mod(i, TestDataFactory.SLOTS.size())];
            appointments.add(TestDataFactory.buildAppointment(doc.Id, patientId, day, slot));
        }

        Test.startTest();
        insert appointments;
        Test.stopTest();

        Assert.areEqual(200, [SELECT COUNT() FROM Task WHERE WhatId IN :appointments]);
        Assert.areEqual(200, [SELECT Total_Appointments__c FROM Patient__c WHERE Id = :patientId].Total_Appointments__c);
        Assert.areEqual(200, doctor().Active_Appointments__c, 'Doctor Workload flow recounts in bulk');
    }

    @IsTest
    static void updateToPastDateRejected() {
        Appointment__c appointment = TestDataFactory.createAppointment(doctor().Id, patients()[0].Id, TOMORROW, '09:00 AM');
        appointment.Appointment_Date__c = Date.today().addDays(-1);

        Test.startTest();
        Database.SaveResult result = Database.update(appointment, false);
        Test.stopTest();

        Assert.isFalse(result.isSuccess());
        Assert.isTrue(result.getErrors()[0].getMessage().contains('past'));
    }

    @IsTest
    static void rescheduleIntoBookedSlotRejected() {
        List<Patient__c> patients = patients();
        TestDataFactory.createAppointment(doctor().Id, patients[0].Id, TOMORROW, '03:00 PM');
        Appointment__c other = TestDataFactory.createAppointment(doctor().Id, patients[1].Id, TOMORROW, '04:00 PM');
        other.Slot__c = '03:00 PM';

        Test.startTest();
        Database.SaveResult result = Database.update(other, false);
        Test.stopTest();

        Assert.isFalse(result.isSuccess());
        Assert.areEqual(AppointmentTriggerHandler.MSG_DOUBLE_BOOKED, result.getErrors()[0].getMessage());
    }

    @IsTest
    static void unrelatedUpdateOfSameAppointmentAllowed() {
        Appointment__c appointment = TestDataFactory.createAppointment(doctor().Id, patients()[0].Id, TOMORROW, '09:00 AM');
        appointment.Status__c = 'Confirmed';

        Test.startTest();
        update appointment;
        Test.stopTest();

        Assert.areEqual('Confirmed', [SELECT Status__c FROM Appointment__c WHERE Id = :appointment.Id].Status__c);
    }

    @IsTest
    static void cancellationFreesDoctorWorkload() {
        Appointment__c appointment = TestDataFactory.createAppointment(doctor().Id, patients()[0].Id, TOMORROW, '09:00 AM');
        appointment.Status__c = 'Cancelled';

        Test.startTest();
        update appointment;
        Test.stopTest();

        Assert.areEqual(0, doctor().Active_Appointments__c, 'Cancelled appointments are not active');
        Assert.isTrue(EmailService.emailsQueued > 0, 'Cancellation email queued');
    }

    @IsTest
    static void deleteAndUndeleteRecalculateCounters() {
        Patient__c patient = patients()[0];
        Appointment__c appointment = TestDataFactory.createAppointment(doctor().Id, patient.Id, TOMORROW, '09:00 AM');

        Test.startTest();
        delete appointment;
        Assert.areEqual(0, doctor().Active_Appointments__c);
        Assert.areEqual(0, [SELECT Total_Appointments__c FROM Patient__c WHERE Id = :patient.Id].Total_Appointments__c);

        undelete appointment;
        Test.stopTest();

        Assert.areEqual(1, doctor().Active_Appointments__c);
        Assert.areEqual(1, [SELECT Total_Appointments__c FROM Patient__c WHERE Id = :patient.Id].Total_Appointments__c);
    }

    @IsTest
    static void patientChangeMovesRollup() {
        List<Patient__c> patients = patients();
        Appointment__c appointment = TestDataFactory.createAppointment(doctor().Id, patients[0].Id, TOMORROW, '09:00 AM');
        appointment.Patient__c = patients[1].Id;

        Test.startTest();
        update appointment;
        Test.stopTest();

        Assert.areEqual(0, [SELECT Total_Appointments__c FROM Patient__c WHERE Id = :patients[0].Id].Total_Appointments__c);
        Assert.areEqual(1, [SELECT Total_Appointments__c FROM Patient__c WHERE Id = :patients[1].Id].Total_Appointments__c);
        Assert.areEqual(patients[1].Email__c, [SELECT Patient_Email__c FROM Appointment__c WHERE Id = :appointment.Id].Patient_Email__c);
    }

    @IsTest
    static void inactiveDoctorCannotBeBooked() {
        Doctor__c doc = doctor();
        update new Doctor__c(Id = doc.Id, Status__c = 'Inactive');

        Test.startTest();
        Database.SaveResult result = Database.insert(TestDataFactory.buildAppointment(doc.Id, patients()[0].Id, TOMORROW, '09:00 AM'), false);
        Test.stopTest();

        Assert.isFalse(result.isSuccess(), 'Validation rule Doctor_Must_Be_Active blocks the booking');
    }
}
