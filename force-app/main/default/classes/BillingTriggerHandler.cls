/**
 * Handler for BillingTrigger.
 *  - before save: defaults Patient from the Appointment, copies the patient email, prices the bill
 *  - after save:  rolls Amount_Due__c up to Patient.Total_Billed_Amount__c and sends insurance
 *                 claims for approved, insured bills
 */
public with sharing class BillingTriggerHandler {
    public static final String STATUS_APPROVED = 'Approved';

    public void beforeInsert(List<Billing__c> bills) {
        populatePatientDetails(bills);
        BillingCalculator.calculateBills(bills);
    }

    public void beforeUpdate(List<Billing__c> bills, Map<Id, Billing__c> oldMap) {
        List<Billing__c> toPrice = new List<Billing__c>();

        for (Billing__c bill : bills) {
            Billing__c old = oldMap.get(bill.Id);
            if (
                bill.Procedure__c != old.Procedure__c ||
                bill.Discount__c != old.Discount__c ||
                bill.Insurance_Coverage__c != old.Insurance_Coverage__c ||
                bill.Total_Charges__c != old.Total_Charges__c
            ) {
                toPrice.add(bill);
            }
        }

        populatePatientDetails(bills);
        BillingCalculator.calculateBills(toPrice);
    }

    public void afterInsert(List<Billing__c> bills) {
        recalculatePatientTotals(patientIdsOf(bills, null));
    }

    public void afterUpdate(List<Billing__c> bills, Map<Id, Billing__c> oldMap) {
        Set<Id> patientIds = new Set<Id>();
        Set<Id> claimIds = new Set<Id>();

        for (Billing__c bill : bills) {
            Billing__c old = oldMap.get(bill.Id);
            if (bill.Amount_Due__c != old.Amount_Due__c || bill.Patient__c != old.Patient__c) {
                addIfNotNull(patientIds, bill.Patient__c);
                addIfNotNull(patientIds, old.Patient__c);
            }
            if (bill.Status__c == STATUS_APPROVED && old.Status__c != STATUS_APPROVED && bill.Insurance__c) {
                claimIds.add(bill.Id);
            }
        }

        recalculatePatientTotals(patientIds);
        SendInsuranceClaimAsync.submitClaims(claimIds);
    }

    public void afterDelete(List<Billing__c> bills) {
        recalculatePatientTotals(patientIdsOf(bills, null));
    }

    private void populatePatientDetails(List<Billing__c> bills) {
        Set<Id> appointmentIds = new Set<Id>();
        for (Billing__c bill : bills) {
            if (bill.Patient__c == null && bill.Appointment__c != null) {
                appointmentIds.add(bill.Appointment__c);
            }
        }

        if (!appointmentIds.isEmpty()) {
            Map<Id, Appointment__c> appointments = new Map<Id, Appointment__c>(
                [SELECT Id, Patient__c FROM Appointment__c WHERE Id IN :appointmentIds]
            );
            for (Billing__c bill : bills) {
                Appointment__c appointment = appointments.get(bill.Appointment__c);
                if (bill.Patient__c == null && appointment != null) {
                    bill.Patient__c = appointment.Patient__c;
                }
            }
        }

        Set<Id> patientIds = patientIdsOf(bills, null);
        if (patientIds.isEmpty()) {
            return;
        }

        Map<Id, Patient__c> patients = new Map<Id, Patient__c>([SELECT Id, Email__c FROM Patient__c WHERE Id IN :patientIds]);
        for (Billing__c bill : bills) {
            Patient__c patient = patients.get(bill.Patient__c);
            if (patient != null && String.isNotBlank(patient.Email__c)) {
                bill.Patient_Email__c = patient.Email__c;
            }
        }
    }

    /** Apex roll-up: Billing reaches the patient through a lookup, so a native roll-up summary is not possible. */
    @TestVisible
    private static void recalculatePatientTotals(Set<Id> patientIds) {
        if (patientIds.isEmpty()) {
            return;
        }

        Map<Id, Decimal> totals = new Map<Id, Decimal>();
        for (AggregateResult row : [
            SELECT Patient__c patientId, SUM(Amount_Due__c) total
            FROM Billing__c
            WHERE Patient__c IN :patientIds
            GROUP BY Patient__c
        ]) {
            totals.put((Id) row.get('patientId'), (Decimal) row.get('total'));
        }

        List<Patient__c> patients = new List<Patient__c>();
        for (Id patientId : patientIds) {
            Decimal total = totals.get(patientId);
            patients.add(new Patient__c(Id = patientId, Total_Billed_Amount__c = total == null ? 0 : total));
        }
        update patients;
    }

    private static Set<Id> patientIdsOf(List<Billing__c> bills, Set<Id> ids) {
        Set<Id> result = ids == null ? new Set<Id>() : ids;
        for (Billing__c bill : bills) {
            addIfNotNull(result, bill.Patient__c);
        }
        return result;
    }

    private static void addIfNotNull(Set<Id> ids, Id value) {
        if (value != null) {
            ids.add(value);
        }
    }
}
