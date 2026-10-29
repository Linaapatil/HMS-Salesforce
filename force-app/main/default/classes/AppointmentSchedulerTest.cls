@IsTest(SeeAllData=false)
private class AppointmentSchedulerTest {
    private static final Date TOMORROW = Date.today().addDays(1);

    @TestSetup
    static void setup() {
        Department__c department = TestDataFactory.createDepartment('Neurology');
        Doctor__c doctor = TestDataFactory.createDoctor(department.Id);
        Doctor__c onLeave = TestDataFactory.buildDoctor(department.Id);
        onLeave.Status__c = 'On Leave';
        insert onLeave;

        List<Patient__c> patients = TestDataFactory.createPatients(2);
        Appointment__c cancelled = TestDataFactory.buildAppointment(doctor.Id, patients[1].Id, TOMORROW, '10:00 AM');
        cancelled.Status__c = 'Cancelled';
        insert new List<Appointment__c>{ TestDataFactory.buildAppointment(doctor.Id, patients[0].Id, TOMORROW, '09:00 AM'), cancelled };
    }

    private static Doctor__c activeDoctor() {
        return [SELECT Id FROM Doctor__c WHERE Status__c = 'Active' LIMIT 1];
    }

    @IsTest
    static void availableSlotsExcludeBookedButNotCancelled() {
        Id doctorId = activeDoctor().Id;

        Test.startTest();
        Map<Date, List<String>> slots = AppointmentScheduler.getAvailableSlots(doctorId, TOMORROW, TOMORROW.addDays(1));
        List<String> forDay = AppointmentScheduler.getAvailableSlotsForDay(doctorId, TOMORROW);
        Test.stopTest();

        Integer allSlots = Appointment__c.Slot__c.getDescribe().getPicklistValues().size();
        Assert.areEqual(2, slots.size());
        Assert.isFalse(slots.get(TOMORROW).contains('09:00 AM'), 'Booked slot removed');
        Assert.isTrue(slots.get(TOMORROW).contains('10:00 AM'), 'Cancelled slot is free again');
        Assert.areEqual(allSlots - 1, slots.get(TOMORROW).size());
        Assert.areEqual(allSlots, slots.get(TOMORROW.addDays(1)).size());
        Assert.areEqual(slots.get(TOMORROW), forDay);
        Assert.isTrue(AppointmentScheduler.getAvailableSlotsForDay(null, TOMORROW).isEmpty());
    }

    @IsTest
    static void invalidRangesRejected() {
        Id doctorId = activeDoctor().Id;
        List<String> messages = new List<String>();

        Test.startTest();
        for (List<Object> args : new List<List<Object>>{
            new List<Object>{ null, TOMORROW, TOMORROW },
            new List<Object>{ doctorId, TOMORROW, Date.today() },
            new List<Object>{ doctorId, TOMORROW, TOMORROW.addDays(40) }
        }) {
            try {
                AppointmentScheduler.getAvailableSlots((Id) args[0], (Date) args[1], (Date) args[2]);
            } catch (HospitalException e) {
                messages.add(e.getMessage());
            }
        }
        Test.stopTest();

        Assert.areEqual(3, messages.size());
    }

    @IsTest
    static void doctorScheduleForDay() {
        Id doctorId = activeDoctor().Id;

        Test.startTest();
        List<Appointment__c> schedule = AppointmentScheduler.getAppointmentsByDoctor(doctorId, TOMORROW);
        List<Appointment__c> none = AppointmentScheduler.getAppointmentsByDoctor(null, TOMORROW);
        Test.stopTest();

        Assert.areEqual(2, schedule.size());
        Assert.isNotNull(schedule[0].Patient__r.Full_Name__c);
        Assert.isTrue(none.isEmpty());
    }

    @IsTest
    static void availableDoctorsExcludesDoctorsOnLeave() {
        Test.startTest();
        List<Doctor__c> doctors = AppointmentScheduler.getAvailableDoctors();
        Test.stopTest();

        Assert.areEqual(1, doctors.size());
    }

    @IsTest
    static void currentDoctorLinkedToRunningUser() {
        Doctor__c doctor = activeDoctor();

        Test.startTest();
        Id before = AppointmentScheduler.getCurrentDoctorId();
        update new Doctor__c(Id = doctor.Id, User__c = UserInfo.getUserId());
        Id afterLink = AppointmentScheduler.getCurrentDoctorId();
        Test.stopTest();

        Assert.isNull(before);
        Assert.areEqual(doctor.Id, afterLink);
    }

    @IsTest
    static void invocableRecalculatesWorkload() {
        Doctor__c doctor = activeDoctor();
        update new Doctor__c(Id = doctor.Id, Active_Appointments__c = 99);

        Test.startTest();
        DoctorWorkloadService.recalculateFromFlow(new List<Id>{ doctor.Id, null });
        Test.stopTest();

        Assert.areEqual(1, [SELECT Active_Appointments__c FROM Doctor__c WHERE Id = :doctor.Id].Active_Appointments__c);
    }
}
