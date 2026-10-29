/**
 * Business logic for patient operations: search, age group and duplicate merging.
 */
public with sharing class PatientService {
    /** Child (0-12), Teen (13-19), Adult (20-59), Senior (60+). */
    public static String calculateAgeGroup(Integer age) {
        if (age == null || age < 0) {
            return 'Unknown';
        }
        if (age <= 12) {
            return 'Child';
        } else if (age <= 19) {
            return 'Teen';
        } else if (age <= 59) {
            return 'Adult';
        }
        return 'Senior';
    }

    public static String calculateAgeGroup(Date dateOfBirth) {
        return calculateAgeGroup(calculateAge(dateOfBirth));
    }

    public static Integer calculateAge(Date dateOfBirth) {
        if (dateOfBirth == null || dateOfBirth > Date.today()) {
            return null;
        }
        Date today = Date.today();
        Integer age = today.year() - dateOfBirth.year();
        if (today.month() < dateOfBirth.month() || (today.month() == dateOfBirth.month() && today.day() < dateOfBirth.day())) {
            age--;
        }
        return age;
    }

    /** All patients (including the given ones) sharing an SSN with any of the given patients. */
    public static List<Patient__c> findDuplicates(List<Patient__c> patients) {
        Set<String> ssns = new Set<String>();
        for (Patient__c patient : patients) {
            if (String.isNotBlank(patient.SSN__c)) {
                ssns.add(patient.SSN__c);
            }
        }
        if (ssns.isEmpty()) {
            return new List<Patient__c>();
        }
        return [
            SELECT Id, Name, Full_Name__c, SSN__c, DOB__c, CreatedDate
            FROM Patient__c
            WHERE SSN__c IN :ssns
            ORDER BY SSN__c, CreatedDate ASC, Name ASC
        ];
    }

    /**
     * Merges patients that share an SSN. The oldest record per SSN is kept as master; appointments,
     * billing and lab results are re-parented to it and the duplicates are deleted.
     * Returns the number of duplicates removed.
     */
    public static Integer mergeDuplicates(List<Patient__c> patients) {
        Map<String, Id> masterBySsn = new Map<String, Id>();
        Map<Id, Id> masterByDuplicate = new Map<Id, Id>();

        for (Patient__c patient : findDuplicates(patients)) {
            if (!masterBySsn.containsKey(patient.SSN__c)) {
                masterBySsn.put(patient.SSN__c, patient.Id);
            } else {
                masterByDuplicate.put(patient.Id, masterBySsn.get(patient.SSN__c));
            }
        }
        if (masterByDuplicate.isEmpty()) {
            return 0;
        }

        Set<Id> duplicateIds = masterByDuplicate.keySet();

        List<Appointment__c> appointments = [SELECT Id, Patient__c FROM Appointment__c WHERE Patient__c IN :duplicateIds];
        for (Appointment__c appointment : appointments) {
            appointment.Patient__c = masterByDuplicate.get(appointment.Patient__c);
        }
        List<Billing__c> bills = [SELECT Id, Patient__c FROM Billing__c WHERE Patient__c IN :duplicateIds];
        for (Billing__c bill : bills) {
            bill.Patient__c = masterByDuplicate.get(bill.Patient__c);
        }
        List<Lab_Result__c> labResults = [SELECT Id, Patient__c FROM Lab_Result__c WHERE Patient__c IN :duplicateIds];
        for (Lab_Result__c labResult : labResults) {
            labResult.Patient__c = masterByDuplicate.get(labResult.Patient__c);
        }

        update appointments;
        update bills;
        update labResults;
        delete [SELECT Id FROM Patient__c WHERE Id IN :duplicateIds];
        return duplicateIds.size();
    }

    /** Used by the patientSearchBar LWC: matches patient name, Patient ID (PAT-0001) or Salesforce record Id. */
    @AuraEnabled(cacheable=true)
    public static List<Patient__c> searchPatients(String searchTerm) {
        if (String.isBlank(searchTerm) || searchTerm.trim().length() < 2) {
            return new List<Patient__c>();
        }

        String term = searchTerm.trim();
        String likeTerm = '%' + term + '%';
        Id recordId = toIdOrNull(term);

        return [
            SELECT Id, Name, Full_Name__c, DOB__c, Age__c, Blood_Group__c, Phone__c, Email__c, Primary_Department__c
            FROM Patient__c
            WHERE Full_Name__c LIKE :likeTerm OR Name LIKE :likeTerm OR Id = :recordId
            WITH USER_MODE
            ORDER BY Full_Name__c NULLS LAST, Name
            LIMIT 20
        ];
    }

    private static Id toIdOrNull(String value) {
        if (value.length() != 15 && value.length() != 18) {
            return null;
        }
        try {
            Id candidate = Id.valueOf(value);
            return candidate.getSobjectType() == Patient__c.SObjectType ? candidate : null;
        } catch (Exception e) {
            return null;
        }
    }
}
