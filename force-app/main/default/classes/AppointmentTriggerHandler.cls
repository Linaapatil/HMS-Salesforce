/**
 * Handler for AppointmentTrigger (one trigger per object).
 * All SOQL is outside loops and all DML is done on collections.
 *
 * Doctor.Active_Appointments__c is updated by the "Doctor Workload" record-triggered flow on
 * create; this handler recounts it (via DoctorWorkloadService) whenever an appointment is
 * cancelled, completed, re-assigned, deleted or undeleted.
 */
public with sharing class AppointmentTriggerHandler {
    public static final String STATUS_REQUESTED = 'Requested';
    public static final String STATUS_CONFIRMED = 'Confirmed';
    public static final String STATUS_COMPLETED = 'Completed';
    public static final String STATUS_CANCELLED = 'Cancelled';

    public static final String MSG_DATE_REQUIRED = 'Appointment Date is required.';
    public static final String MSG_PAST_DATE = 'Appointment Date cannot be in the past.';
    public static final String MSG_DOUBLE_BOOKED = 'Doctor is already booked for this date and slot.';

    public void beforeInsert(List<Appointment__c> appointments) {
        List<Appointment__c> toCheck = new List<Appointment__c>();

        for (Appointment__c appointment : appointments) {
            if (validateDate(appointment) && appointment.Status__c != STATUS_CANCELLED) {
                toCheck.add(appointment);
            }
        }

        detectConflicts(toCheck);
        populatePatientEmail(appointments, null);
    }

    public void beforeUpdate(List<Appointment__c> appointments, Map<Id, Appointment__c> oldMap) {
        List<Appointment__c> toCheck = new List<Appointment__c>();

        for (Appointment__c appointment : appointments) {
            Appointment__c old = oldMap.get(appointment.Id);
            Boolean rescheduled =
                appointment.Appointment_Date__c != old.Appointment_Date__c ||
                appointment.Slot__c != old.Slot__c ||
                appointment.Doctor__c != old.Doctor__c;
            Boolean reactivated = old.Status__c == STATUS_CANCELLED && appointment.Status__c != STATUS_CANCELLED;

            // Only a changed date is validated, so past appointments can still be completed.
            if (appointment.Appointment_Date__c != old.Appointment_Date__c && !validateDate(appointment)) {
                continue;
            }
            if ((rescheduled || reactivated) && appointment.Status__c != STATUS_CANCELLED) {
                toCheck.add(appointment);
            }
        }

        detectConflicts(toCheck);
        populatePatientEmail(appointments, oldMap);
    }

    public void afterInsert(List<Appointment__c> appointments) {
        List<Task> tasks = new List<Task>();
        Set<Id> patientIds = new Set<Id>();

        for (Appointment__c appointment : appointments) {
            tasks.add(
                new Task(
                    Subject = 'Confirm appointment with patient',
                    Description = 'Call the patient to confirm appointment ' + appointment.Name + '.',
                    WhatId = appointment.Id,
                    OwnerId = UserInfo.getUserId(),
                    ActivityDate = Date.today(),
                    Status = 'Not Started',
                    Priority = 'Normal'
                )
            );
            addIfNotNull(patientIds, appointment.Patient__c);
        }

        insert tasks;
        recalculatePatientTotals(patientIds);
    }

    public void afterUpdate(List<Appointment__c> appointments, Map<Id, Appointment__c> oldMap) {
        Set<Id> doctorIds = new Set<Id>();
        Set<Id> patientIds = new Set<Id>();
        List<Appointment__c> cancelled = new List<Appointment__c>();

        for (Appointment__c appointment : appointments) {
            Appointment__c old = oldMap.get(appointment.Id);

            if (appointment.Status__c == STATUS_CANCELLED && old.Status__c != STATUS_CANCELLED) {
                cancelled.add(appointment);
            }
            if (appointment.Status__c != old.Status__c || appointment.Doctor__c != old.Doctor__c) {
                addIfNotNull(doctorIds, appointment.Doctor__c);
                addIfNotNull(doctorIds, old.Doctor__c);
            }
            if (appointment.Patient__c != old.Patient__c) {
                addIfNotNull(patientIds, appointment.Patient__c);
                addIfNotNull(patientIds, old.Patient__c);
            }
        }

        recalculateDoctorWorkload(doctorIds);
        recalculatePatientTotals(patientIds);
        EmailService.sendCancellationEmails(cancelled);
    }

    public void afterDelete(List<Appointment__c> appointments) {
        recalculateRelated(appointments);
    }

    public void afterUndelete(List<Appointment__c> appointments) {
        recalculateRelated(appointments);
    }

    private void recalculateRelated(List<Appointment__c> appointments) {
        Set<Id> doctorIds = new Set<Id>();
        Set<Id> patientIds = new Set<Id>();

        for (Appointment__c appointment : appointments) {
            addIfNotNull(doctorIds, appointment.Doctor__c);
            addIfNotNull(patientIds, appointment.Patient__c);
        }

        recalculateDoctorWorkload(doctorIds);
        recalculatePatientTotals(patientIds);
    }

    /** Returns false (and adds an error) when the appointment date is missing or in the past. */
    private Boolean validateDate(Appointment__c appointment) {
        if (appointment.Appointment_Date__c == null) {
            appointment.addError(MSG_DATE_REQUIRED);
            return false;
        }
        if (appointment.Appointment_Date__c < Date.today()) {
            appointment.Appointment_Date__c.addError(MSG_PAST_DATE);
            return false;
        }
        return true;
    }

    /** Flags appointments that clash with each other or with existing bookings for the same doctor, date and slot. */
    private void detectConflicts(List<Appointment__c> appointments) {
        Set<Id> doctorIds = new Set<Id>();
        Set<Date> dates = new Set<Date>();
        Set<Id> selfIds = new Set<Id>();
        Set<String> batchKeys = new Set<String>();

        for (Appointment__c appointment : appointments) {
            if (appointment.Doctor__c == null || appointment.Slot__c == null) {
                continue;
            }
            doctorIds.add(appointment.Doctor__c);
            dates.add(appointment.Appointment_Date__c);
            addIfNotNull(selfIds, appointment.Id);

            if (!batchKeys.add(slotKey(appointment))) {
                appointment.addError(MSG_DOUBLE_BOOKED);
            }
        }

        if (doctorIds.isEmpty()) {
            return;
        }

        Set<String> bookedKeys = new Set<String>();
        for (Appointment__c existing : [
            SELECT Doctor__c, Appointment_Date__c, Slot__c
            FROM Appointment__c
            WHERE
                Doctor__c IN :doctorIds
                AND Appointment_Date__c IN :dates
                AND Status__c != :STATUS_CANCELLED
                AND Id NOT IN :selfIds
        ]) {
            bookedKeys.add(slotKey(existing));
        }

        for (Appointment__c appointment : appointments) {
            if (appointment.Doctor__c != null && appointment.Slot__c != null && bookedKeys.contains(slotKey(appointment))) {
                appointment.addError(MSG_DOUBLE_BOOKED);
            }
        }
    }

    /** Copies the patient's email onto the appointment so email alerts and reminders can use it. */
    private void populatePatientEmail(List<Appointment__c> appointments, Map<Id, Appointment__c> oldMap) {
        Set<Id> patientIds = new Set<Id>();

        for (Appointment__c appointment : appointments) {
            Boolean patientChanged = oldMap != null && appointment.Patient__c != oldMap.get(appointment.Id).Patient__c;
            if (appointment.Patient__c != null && (String.isBlank(appointment.Patient_Email__c) || patientChanged)) {
                patientIds.add(appointment.Patient__c);
            }
        }

        if (patientIds.isEmpty()) {
            return;
        }

        Map<Id, Patient__c> patients = new Map<Id, Patient__c>([SELECT Id, Email__c FROM Patient__c WHERE Id IN :patientIds]);

        for (Appointment__c appointment : appointments) {
            Patient__c patient = patients.get(appointment.Patient__c);
            if (patient != null && String.isNotBlank(patient.Email__c)) {
                appointment.Patient_Email__c = patient.Email__c;
            }
        }
    }

    private static void recalculateDoctorWorkload(Set<Id> doctorIds) {
        DoctorWorkloadService.recalculate(doctorIds);
    }

    /** Apex roll-up: Appointment -> Patient is a lookup, so a native roll-up summary is not possible. */
    @TestVisible
    private static void recalculatePatientTotals(Set<Id> patientIds) {
        if (patientIds.isEmpty()) {
            return;
        }

        Map<Id, Integer> counts = new Map<Id, Integer>();
        for (AggregateResult row : [
            SELECT Patient__c patientId, COUNT(Id) total
            FROM Appointment__c
            WHERE Patient__c IN :patientIds
            GROUP BY Patient__c
        ]) {
            counts.put((Id) row.get('patientId'), (Integer) row.get('total'));
        }

        List<Patient__c> patients = new List<Patient__c>();
        for (Id patientId : patientIds) {
            Integer total = counts.get(patientId);
            patients.add(new Patient__c(Id = patientId, Total_Appointments__c = total == null ? 0 : total));
        }
        update patients;
    }

    private static String slotKey(Appointment__c appointment) {
        return appointment.Doctor__c + '|' + appointment.Appointment_Date__c + '|' + appointment.Slot__c;
    }

    private static void addIfNotNull(Set<Id> ids, Id value) {
        if (value != null) {
            ids.add(value);
        }
    }
}
