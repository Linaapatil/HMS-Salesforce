@IsTest(SeeAllData=false)
private class HospitalDashboardControllerTest {
    @TestSetup
    static void setup() {
        Department__c cardiology = TestDataFactory.createDepartment('Cardiology');
        TestDataFactory.createDepartment('Orthopedics');
        Doctor__c doctor = TestDataFactory.createDoctor(cardiology.Id);
        Doctor__c unassigned = TestDataFactory.createDoctor(null);
        List<Patient__c> patients = TestDataFactory.createPatients(3);

        List<Appointment__c> appointments = new List<Appointment__c>{
            TestDataFactory.buildAppointment(doctor.Id, patients[0].Id, Date.today(), '06:00 PM'),
            TestDataFactory.buildAppointment(doctor.Id, patients[1].Id, Date.today(), '07:00 PM'),
            TestDataFactory.buildAppointment(unassigned.Id, patients[2].Id, Date.today(), '08:00 PM')
        };
        appointments[1].Status__c = 'Completed';
        insert appointments;

        Billing__c bill = TestDataFactory.buildBilling(patients[0].Id, TestDataFactory.createProcedure(10000).Id, appointments[0].Id);
        bill.Status__c = 'Submitted';
        insert bill;
    }

    @IsTest
    static void todayStats() {
        Test.startTest();
        HospitalDashboardController.TodayStats stats = HospitalDashboardController.getTodayStats();
        Test.stopTest();

        Assert.areEqual(3, stats.totalAppointments);
        Assert.areEqual(1, stats.completed);
        Assert.areEqual(2, stats.upcoming);
        Assert.areEqual(0, stats.cancelled);
        Assert.areEqual(2, stats.activeDoctors);
    }

    @IsTest
    static void revenueSummary() {
        Test.startTest();
        HospitalDashboardController.RevenueSummary revenue = HospitalDashboardController.getRevenueSummary();
        Test.stopTest();

        // 10000 + the default charge the "Billing Auto-Create" flow adds for the completed appointment.
        Assert.isTrue(revenue.monthRevenue >= 7200);
        Assert.isTrue(revenue.monthBills >= 1);
        Assert.areEqual(1, revenue.pendingApprovals);
    }

    @IsTest
    static void departmentSummaryIncludesUnassigned() {
        Test.startTest();
        List<HospitalDashboardController.DepartmentSummary> rows = HospitalDashboardController.getDepartmentSummary();
        Test.stopTest();

        Map<String, HospitalDashboardController.DepartmentSummary> byName = new Map<String, HospitalDashboardController.DepartmentSummary>();
        for (HospitalDashboardController.DepartmentSummary row : rows) {
            byName.put(row.department, row);
        }
        Assert.areEqual(3, rows.size());
        Assert.areEqual(2, byName.get('Cardiology').appointmentCount);
        Assert.areEqual(0, byName.get('Orthopedics').appointmentCount);
        Assert.areEqual(1, byName.get('Not Assigned').appointmentCount);
        Assert.areEqual(40, byName.get('Cardiology').bedCount);
    }

    @IsTest
    static void bedOccupancy() {
        Test.startTest();
        HospitalDashboardController.BedOccupancy occupancy = HospitalDashboardController.getBedOccupancy();
        Test.stopTest();

        Assert.areEqual(80, occupancy.totalBeds);
        Assert.areEqual(50, occupancy.occupiedBeds);
        Assert.areEqual(62.5, occupancy.occupancyPercent);
    }

    @IsTest
    static void emailServiceHelpers() {
        Doctor__c doctor = [SELECT Id, Email__c FROM Doctor__c WHERE Email__c != NULL LIMIT 1];

        Test.startTest();
        EmailService.sendDoctorEmails(new List<Doctor__c>{ doctor }, 'Schedule', 'Your schedule changed.');
        EmailService.sendEmail(new List<String>{ ' ', null }, 'Ignored', 'No valid recipients');
        EmailService.sendEmail(null, 'Ignored', 'No recipients');
        Test.stopTest();

        Assert.areEqual(1, EmailService.emailsQueued);
    }
}
