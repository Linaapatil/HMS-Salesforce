/**
 * Tests for the SOAP insurance verification and the @future insurance claim callout.
 */
@IsTest(SeeAllData=false)
private class IntegrationServicesTest {
    @IsTest
    static void verifyCoverageCovered() {
        Patient__c patient = TestDataFactory.createPatient();
        Test.setMock(WebServiceMock.class, new InsuranceVerificationMock(true, 80));

        Test.startTest();
        InsuranceVerificationService.CoverageResult result = InsuranceVerificationService.verifyPatientCoverage(patient.Id);
        Test.stopTest();

        Assert.isTrue(result.covered);
        Assert.areEqual(80, result.coveragePercent);
        Assert.isTrue(result.message.contains(patient.Insurance_Policy_No__c));
    }

    @IsTest
    static void verifyCoverageNotCovered() {
        Patient__c patient = TestDataFactory.createPatient();
        Test.setMock(WebServiceMock.class, new InsuranceVerificationMock(false, null));

        Test.startTest();
        InsuranceVerificationService.CoverageResult result = InsuranceVerificationService.verifyPatientCoverage(patient.Id);
        Test.stopTest();

        Assert.isFalse(result.covered);
        Assert.areEqual(0, result.coveragePercent);
    }

    @IsTest
    static void verifyCoverageWithoutPolicyFails() {
        Patient__c patient = TestDataFactory.buildPatient();
        patient.Insurance_Policy_No__c = null;
        insert patient;

        Test.startTest();
        try {
            InsuranceVerificationService.verifyPatientCoverage(patient.Id);
            Assert.fail('Expected AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e);
        }
        Test.stopTest();
    }

    @IsTest
    static void futureClaimPostsJson() {
        Test.setMock(HttpCalloutMock.class, new HmsHttpCalloutMock(201, '{"claimId":"CLM-9"}'));
        Doctor__c doctor = TestDataFactory.createDoctor();
        Patient__c patient = TestDataFactory.createPatient();
        Appointment__c appointment = TestDataFactory.createAppointment(doctor.Id, patient.Id, Date.today().addDays(1), '09:00 AM');
        Billing__c bill = TestDataFactory.createBilling(patient.Id, TestDataFactory.createProcedure(5000).Id, appointment.Id);

        Test.startTest();
        SendInsuranceClaimAsync.sendClaim(bill.Id);
        Test.stopTest();

        Assert.areEqual(1, HmsHttpCalloutMock.requests.size());
        HttpRequest request = HmsHttpCalloutMock.requests[0];
        Assert.areEqual('POST', request.getMethod());
        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(request.getBody());
        Assert.areEqual(String.valueOf(bill.Id), (String) payload.get('billingId'));
        Assert.areEqual('Star Health', payload.get('provider'));
    }

    @IsTest
    static void failedClaimIsLoggedNotThrown() {
        Test.setMock(HttpCalloutMock.class, new HmsHttpCalloutMock(500, '{"error":"down"}'));
        Doctor__c doctor = TestDataFactory.createDoctor();
        Patient__c patient = TestDataFactory.createPatient();
        Appointment__c appointment = TestDataFactory.createAppointment(doctor.Id, patient.Id, Date.today().addDays(1), '09:00 AM');
        Billing__c bill = TestDataFactory.createBilling(patient.Id, TestDataFactory.createProcedure(5000).Id, appointment.Id);

        Test.startTest();
        SendInsuranceClaimAsync.sendClaims(new List<Id>{ bill.Id });
        Test.stopTest();

        Assert.areEqual(1, HmsHttpCalloutMock.requests.size());
    }

    @IsTest
    static void submitClaimsIgnoresEmptyInput() {
        Test.startTest();
        SendInsuranceClaimAsync.submitClaims(new Set<Id>());
        SendInsuranceClaimAsync.submitClaims(null);
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'Future']);
    }
}
