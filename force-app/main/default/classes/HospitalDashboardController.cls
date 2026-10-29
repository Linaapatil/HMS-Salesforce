/**
 * Data for the hospitalDashboard LWC: today's stats, revenue, bed occupancy and the
 * department-wise summary table. Each method is called imperatively so the dashboard
 * can refresh them after an appointment is booked.
 */
public with sharing class HospitalDashboardController {
    @AuraEnabled
    public static TodayStats getTodayStats() {
        TodayStats stats = new TodayStats();
        Date today = Date.today();

        for (AggregateResult row : [
            SELECT Status__c status, COUNT(Id) total
            FROM Appointment__c
            WHERE Appointment_Date__c = :today
            WITH USER_MODE
            GROUP BY Status__c
        ]) {
            Integer total = (Integer) row.get('total');
            String status = (String) row.get('status');
            stats.totalAppointments += total;
            if (status == 'Completed') {
                stats.completed += total;
            } else if (status == 'Cancelled') {
                stats.cancelled += total;
            } else {
                stats.upcoming += total;
            }
        }

        stats.activeDoctors = [SELECT COUNT() FROM Doctor__c WHERE Status__c = 'Active' WITH USER_MODE];
        return stats;
    }

    @AuraEnabled
    public static RevenueSummary getRevenueSummary() {
        RevenueSummary summary = new RevenueSummary();
        Date monthStart = Date.today().toStartOfMonth();
        Datetime monthStartTime = Datetime.newInstance(monthStart, Time.newInstance(0, 0, 0, 0));

        AggregateResult[] totals = [
            SELECT SUM(Amount_Due__c) due, SUM(Insurance_Amount__c) insured, COUNT(Id) bills
            FROM Billing__c
            WHERE CreatedDate >= :monthStartTime
            WITH USER_MODE
        ];
        summary.monthRevenue = nullToZero((Decimal) totals[0].get('due'));
        summary.monthInsurance = nullToZero((Decimal) totals[0].get('insured'));
        summary.monthBills = (Integer) totals[0].get('bills');
        summary.pendingApprovals = [SELECT COUNT() FROM Billing__c WHERE Status__c = 'Submitted' WITH USER_MODE];
        return summary;
    }

    @AuraEnabled
    public static List<DepartmentSummary> getDepartmentSummary() {
        Date today = Date.today();
        Map<Id, Integer> appointmentsByDepartment = new Map<Id, Integer>();

        for (AggregateResult row : [
            SELECT Doctor__r.Department__c departmentId, COUNT(Id) total
            FROM Appointment__c
            WHERE Appointment_Date__c = :today AND Status__c != 'Cancelled'
            WITH USER_MODE
            GROUP BY Doctor__r.Department__c
        ]) {
            appointmentsByDepartment.put((Id) row.get('departmentId'), (Integer) row.get('total'));
        }

        List<DepartmentSummary> summaries = new List<DepartmentSummary>();
        for (Department__c department : [
            SELECT Id, Name, Floor__c, Bed_Count__c, Occupied_Beds__c, Bed_Occupancy__c, HOD__r.Name
            FROM Department__c
            WITH USER_MODE
            ORDER BY Name
        ]) {
            DepartmentSummary summary = new DepartmentSummary();
            summary.departmentId = department.Id;
            summary.department = department.Name;
            summary.headOfDepartment = department.HOD__r?.Name;
            summary.floor = department.Floor__c;
            summary.bedCount = nullToZero(department.Bed_Count__c);
            summary.occupiedBeds = nullToZero(department.Occupied_Beds__c);
            summary.occupancyPercent = nullToZero(department.Bed_Occupancy__c);
            summary.appointmentCount = appointmentsByDepartment.containsKey(department.Id) ? appointmentsByDepartment.get(department.Id) : 0;
            summaries.add(summary);
        }

        if (appointmentsByDepartment.containsKey(null)) {
            DepartmentSummary unassigned = new DepartmentSummary();
            unassigned.department = 'Not Assigned';
            unassigned.appointmentCount = appointmentsByDepartment.get(null);
            summaries.add(unassigned);
        }
        return summaries;
    }

    @AuraEnabled
    public static BedOccupancy getBedOccupancy() {
        BedOccupancy occupancy = new BedOccupancy();
        AggregateResult[] totals = [SELECT SUM(Bed_Count__c) beds, SUM(Occupied_Beds__c) occupied FROM Department__c WITH USER_MODE];
        occupancy.totalBeds = nullToZero((Decimal) totals[0].get('beds'));
        occupancy.occupiedBeds = nullToZero((Decimal) totals[0].get('occupied'));
        occupancy.occupancyPercent = occupancy.totalBeds == 0 ? 0 : (occupancy.occupiedBeds * 100 / occupancy.totalBeds).setScale(1);
        return occupancy;
    }

    private static Decimal nullToZero(Decimal value) {
        return value == null ? 0 : value;
    }

    public class TodayStats {
        @AuraEnabled
        public Integer totalAppointments = 0;
        @AuraEnabled
        public Integer upcoming = 0;
        @AuraEnabled
        public Integer completed = 0;
        @AuraEnabled
        public Integer cancelled = 0;
        @AuraEnabled
        public Integer activeDoctors = 0;
    }

    public class RevenueSummary {
        @AuraEnabled
        public Decimal monthRevenue = 0;
        @AuraEnabled
        public Decimal monthInsurance = 0;
        @AuraEnabled
        public Integer monthBills = 0;
        @AuraEnabled
        public Integer pendingApprovals = 0;
    }

    public class BedOccupancy {
        @AuraEnabled
        public Decimal totalBeds = 0;
        @AuraEnabled
        public Decimal occupiedBeds = 0;
        @AuraEnabled
        public Decimal occupancyPercent = 0;
    }

    public class DepartmentSummary {
        @AuraEnabled
        public Id departmentId;
        @AuraEnabled
        public String department;
        @AuraEnabled
        public String headOfDepartment;
        @AuraEnabled
        public Decimal floor;
        @AuraEnabled
        public Decimal bedCount = 0;
        @AuraEnabled
        public Decimal occupiedBeds = 0;
        @AuraEnabled
        public Decimal occupancyPercent = 0;
        @AuraEnabled
        public Integer appointmentCount = 0;
    }
}
