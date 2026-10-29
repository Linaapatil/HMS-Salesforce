/**
 * Apex REST web service for the external EHR system.
 *
 *   GET /services/apexrest/HMS/patient/{id}
 *
 * {id} may be the Salesforce record Id or the Patient ID (e.g. PAT-0001).
 * SSN is never exposed.
 */
@RestResource(urlMapping='/HMS/patient/*')
global with sharing class PatientRestService {
    @HttpGet
    global static PatientInfo getPatient() {
        RestRequest request = RestContext.request;
        RestResponse response = RestContext.response;
        String key = request.requestURI.substringAfterLast('/');

        if (String.isBlank(key)) {
            response.statusCode = 400;
            return null;
        }

        List<Patient__c> patients = [
            SELECT
                Id,
                Name,
                Full_Name__c,
                DOB__c,
                Age__c,
                Blood_Group__c,
                Phone__c,
                Email__c,
                Emergency_Contact_Name__c,
                Emergency_Contact__c,
                Total_Appointments__c,
                Last_Appointment_Date__c,
                (
                    SELECT Name, Appointment_Date__c, Slot__c, Status__c, Doctor__r.Name
                    FROM Appointments__r
                    ORDER BY Appointment_Date__c DESC
                    LIMIT 10
                ),
                (SELECT Name, Diagnosis__c, Prescription__c, Report_URL__c FROM Medical_Records__r ORDER BY CreatedDate DESC LIMIT 10)
            FROM Patient__c
            WHERE Name = :key OR Id = :toIdOrNull(key)
            LIMIT 1
        ];

        if (patients.isEmpty()) {
            response.statusCode = 404;
            return null;
        }

        response.statusCode = 200;
        return new PatientInfo(patients[0]);
    }

    private static Id toIdOrNull(String value) {
        try {
            return (value.length() == 15 || value.length() == 18) ? Id.valueOf(value) : null;
        } catch (Exception e) {
            return null;
        }
    }

    global class PatientInfo {
        global Id recordId;
        global String patientId;
        global String name;
        global Date dateOfBirth;
        global Decimal age;
        global String bloodGroup;
        global String phone;
        global String email;
        global String emergencyContactName;
        global String emergencyContactPhone;
        global Decimal totalAppointments;
        global Date lastAppointmentDate;
        global List<AppointmentInfo> appointments = new List<AppointmentInfo>();
        global List<MedicalRecordInfo> medicalRecords = new List<MedicalRecordInfo>();

        PatientInfo(Patient__c patient) {
            recordId = patient.Id;
            patientId = patient.Name;
            name = patient.Full_Name__c;
            dateOfBirth = patient.DOB__c;
            age = patient.Age__c;
            bloodGroup = patient.Blood_Group__c;
            phone = patient.Phone__c;
            email = patient.Email__c;
            emergencyContactName = patient.Emergency_Contact_Name__c;
            emergencyContactPhone = patient.Emergency_Contact__c;
            totalAppointments = patient.Total_Appointments__c;
            lastAppointmentDate = patient.Last_Appointment_Date__c;
            for (Appointment__c appointment : patient.Appointments__r) {
                appointments.add(new AppointmentInfo(appointment));
            }
            for (Medical_Record__c record : patient.Medical_Records__r) {
                medicalRecords.add(new MedicalRecordInfo(record));
            }
        }
    }

    global class AppointmentInfo {
        global String appointmentNumber;
        global Date appointmentDate;
        global String slot;
        global String status;
        global String doctor;

        AppointmentInfo(Appointment__c appointment) {
            appointmentNumber = appointment.Name;
            appointmentDate = appointment.Appointment_Date__c;
            slot = appointment.Slot__c;
            status = appointment.Status__c;
            doctor = appointment.Doctor__r?.Name;
        }
    }

    global class MedicalRecordInfo {
        global String recordNumber;
        global String diagnosis;
        global String prescription;
        global String reportUrl;

        MedicalRecordInfo(Medical_Record__c record) {
            recordNumber = record.Name;
            diagnosis = record.Diagnosis__c;
            prescription = record.Prescription__c;
            reportUrl = record.Report_URL__c;
        }
    }
}
