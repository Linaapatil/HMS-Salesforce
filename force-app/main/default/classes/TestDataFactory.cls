/**
 * Centralised test data creation for all HMS objects.
 * Values match the org's restricted picklists and validation rules.
 */
@IsTest
public class TestDataFactory {
    public static final List<String> SLOTS = new List<String>{
        '08:00 AM',
        '09:00 AM',
        '10:00 AM',
        '11:00 AM',
        '12:00 PM',
        '01:00 PM',
        '02:00 PM',
        '03:00 PM',
        '04:00 PM',
        '05:00 PM',
        '06:00 PM',
        '07:00 PM',
        '08:00 PM'
    };

    // Random start: statics reset between @TestSetup and each test method, and License_No__c is unique.
    private static Integer sequence = Math.mod(Math.abs(Crypto.getRandomInteger()), 800000);

    private static Integer nextSequence() {
        return ++sequence;
    }

    /** MCI- followed by six digits, unique within the test run (License_No__c is unique). */
    public static String nextLicenseNumber() {
        return 'MCI-' + String.valueOf(100000 + nextSequence());
    }

    public static Department__c createDepartment(String name) {
        Department__c department = new Department__c(Name = name, Floor__c = 2, Bed_Count__c = 40, Occupied_Beds__c = 25);
        insert department;
        return department;
    }

    public static Doctor__c buildDoctor(Id departmentId) {
        return new Doctor__c(
            Name = 'Dr. Test ' + nextSequence(),
            License_No__c = nextLicenseNumber(),
            Specialization__c = 'General Medicine',
            Status__c = 'Active',
            Availability__c = 'Available',
            Department__c = departmentId,
            Email__c = 'doctor' + sequence + '@medcare.test'
        );
    }

    public static Doctor__c createDoctor() {
        return createDoctor(null);
    }

    public static Doctor__c createDoctor(Id departmentId) {
        Doctor__c doctor = buildDoctor(departmentId);
        insert doctor;
        return doctor;
    }

    public static Patient__c buildPatient() {
        Integer n = nextSequence();
        return new Patient__c(
            Full_Name__c = 'Test Patient ' + n,
            DOB__c = Date.today().addYears(-30),
            Blood_Group__c = 'O+',
            Email__c = 'patient' + n + '@medcare.test',
            Phone__c = '9000000' + String.valueOf(n).leftPad(3, '0'),
            SSN__c = 'SSN-' + String.valueOf(n).leftPad(6, '0'),
            Insurance_Provider__c = 'Star Health',
            Insurance_Policy_No__c = 'POL-' + n
        );
    }

    public static Patient__c createPatient() {
        Patient__c patient = buildPatient();
        insert patient;
        return patient;
    }

    public static List<Patient__c> createPatients(Integer count) {
        List<Patient__c> patients = new List<Patient__c>();
        for (Integer i = 0; i < count; i++) {
            patients.add(buildPatient());
        }
        insert patients;
        return patients;
    }

    public static Procedure__c createProcedure(Decimal price) {
        Procedure__c procedure = new Procedure__c(Name = 'Test Procedure ' + nextSequence(), Price__c = price, Procedure_Code__c = 'PRC-' + sequence);
        insert procedure;
        return procedure;
    }

    public static Appointment__c buildAppointment(Id doctorId, Id patientId, Date appointmentDate, String slot) {
        return new Appointment__c(
            Doctor__c = doctorId,
            Patient__c = patientId,
            Appointment_Date__c = appointmentDate,
            Slot__c = slot,
            Status__c = 'Requested',
            Appointment_Type__c = 'General Consultation'
        );
    }

    public static Appointment__c createAppointment(Id doctorId, Id patientId, Date appointmentDate, String slot) {
        Appointment__c appointment = buildAppointment(doctorId, patientId, appointmentDate, slot);
        insert appointment;
        return appointment;
    }

    public static Billing__c buildBilling(Id patientId, Id procedureId, Id appointmentId) {
        return new Billing__c(
            Patient__c = patientId,
            Procedure__c = procedureId,
            Appointment__c = appointmentId,
            Discount__c = 10,
            Insurance_Coverage__c = 20,
            Status__c = 'Pending'
        );
    }

    public static Billing__c createBilling(Id patientId, Id procedureId, Id appointmentId) {
        Billing__c billing = buildBilling(patientId, procedureId, appointmentId);
        insert billing;
        return billing;
    }

    public static Lab_Result__c buildLabResult(Id patientId, String result) {
        return new Lab_Result__c(Patient__c = patientId, Test_Name__c = 'CBC', Result__c = result, Status__c = 'Pending');
    }
}
