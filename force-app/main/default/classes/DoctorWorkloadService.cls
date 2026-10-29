/**
 * Keeps Doctor__c.Active_Appointments__c (Requested + Confirmed appointments) accurate.
 *
 * Invoked by the "Doctor Workload" record-triggered flow when appointments are created and
 * by AppointmentTriggerHandler on cancel / complete / reassign / delete / undelete.
 * Recounting (instead of +1 / -1) keeps the counter correct for bulk loads, where every
 * flow interview in a batch would otherwise read the same starting value.
 */
public with sharing class DoctorWorkloadService {
    @InvocableMethod(
        label='Recalculate Doctor Workload'
        description='Recounts active (Requested/Confirmed) appointments for the given doctors.'
        category='HMS'
    )
    public static void recalculateFromFlow(List<Id> doctorIds) {
        recalculate(new Set<Id>(doctorIds));
    }

    public static void recalculate(Set<Id> doctorIds) {
        doctorIds.remove(null);
        if (doctorIds.isEmpty()) {
            return;
        }

        Map<Id, Integer> counts = new Map<Id, Integer>();
        for (AggregateResult row : [
            SELECT Doctor__c doctorId, COUNT(Id) total
            FROM Appointment__c
            WHERE Doctor__c IN :doctorIds AND Status__c IN ('Requested', 'Confirmed')
            GROUP BY Doctor__c
        ]) {
            counts.put((Id) row.get('doctorId'), (Integer) row.get('total'));
        }

        List<Doctor__c> doctors = new List<Doctor__c>();
        for (Id doctorId : doctorIds) {
            Integer total = counts.get(doctorId);
            doctors.add(new Doctor__c(Id = doctorId, Active_Appointments__c = total == null ? 0 : total));
        }
        update doctors;
    }
}
