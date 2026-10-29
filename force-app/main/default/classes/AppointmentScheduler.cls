/**
 * Appointment scheduling: available slots for a doctor and schedule queries for the doctor portal LWC.
 */
public with sharing class AppointmentScheduler {
    /** Free slots per day for a doctor in [startDate, endDate]. Cancelled appointments free their slot. */
    public static Map<Date, List<String>> getAvailableSlots(Id doctorId, Date startDate, Date endDate) {
        if (doctorId == null || startDate == null || endDate == null) {
            throw new HospitalException('Doctor and date range are required.');
        }
        if (endDate < startDate) {
            throw new HospitalException('End date cannot be before start date.');
        }
        if (startDate.daysBetween(endDate) > 31) {
            throw new HospitalException('Date range cannot exceed 31 days.');
        }

        List<String> allSlots = new List<String>();
        for (Schema.PicklistEntry entry : Appointment__c.Slot__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                allSlots.add(entry.getValue());
            }
        }

        Map<Date, Set<String>> bookedSlots = new Map<Date, Set<String>>();
        for (Appointment__c appointment : [
            SELECT Appointment_Date__c, Slot__c
            FROM Appointment__c
            WHERE
                Doctor__c = :doctorId
                AND Appointment_Date__c >= :startDate
                AND Appointment_Date__c <= :endDate
                AND Status__c != 'Cancelled'
        ]) {
            if (!bookedSlots.containsKey(appointment.Appointment_Date__c)) {
                bookedSlots.put(appointment.Appointment_Date__c, new Set<String>());
            }
            bookedSlots.get(appointment.Appointment_Date__c).add(appointment.Slot__c);
        }

        Map<Date, List<String>> availableSlots = new Map<Date, List<String>>();
        for (Date day = startDate; day <= endDate; day = day.addDays(1)) {
            Set<String> booked = bookedSlots.containsKey(day) ? bookedSlots.get(day) : new Set<String>();
            List<String> available = new List<String>();
            for (String slot : allSlots) {
                if (!booked.contains(slot)) {
                    available.add(slot);
                }
            }
            availableSlots.put(day, available);
        }
        return availableSlots;
    }

    /** Free slots for one day, for the appointment form. */
    @AuraEnabled(cacheable=true)
    public static List<String> getAvailableSlotsForDay(Id doctorId, Date appointmentDate) {
        if (doctorId == null || appointmentDate == null) {
            return new List<String>();
        }
        return getAvailableSlots(doctorId, appointmentDate, appointmentDate).get(appointmentDate);
    }

    /** doctorScheduleCard: the doctor's appointments (and patient list) for a day. */
    @AuraEnabled(cacheable=true)
    public static List<Appointment__c> getAppointmentsByDoctor(Id doctorId, Date appointmentDate) {
        if (doctorId == null || appointmentDate == null) {
            return new List<Appointment__c>();
        }
        return [
            SELECT Id, Name, Appointment_Date__c, Slot__c, Status__c, Appointment_Type__c, Patient__c, Patient__r.Name, Patient__r.Full_Name__c
            FROM Appointment__c
            WHERE Doctor__c = :doctorId AND Appointment_Date__c = :appointmentDate
            WITH USER_MODE
            ORDER BY Slot__c
        ];
    }

    /** The Doctor__c record linked to the running user, for the "my schedule" doctor portal. */
    @AuraEnabled(cacheable=true)
    public static Id getCurrentDoctorId() {
        List<Doctor__c> doctors = [SELECT Id FROM Doctor__c WHERE User__c = :UserInfo.getUserId() WITH USER_MODE LIMIT 1];
        return doctors.isEmpty() ? null : doctors[0].Id;
    }

    /** Active doctors that can be booked. */
    @AuraEnabled(cacheable=true)
    public static List<Doctor__c> getAvailableDoctors() {
        return [
            SELECT Id, Name, Specialization__c, Department__r.Name, Availability__c, Active_Appointments__c
            FROM Doctor__c
            WHERE Status__c = 'Active'
            WITH USER_MODE
            ORDER BY Name
            LIMIT 200
        ];
    }
}
