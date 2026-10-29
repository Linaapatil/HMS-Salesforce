@IsTest(SeeAllData=false)
private class BillingCalculatorTest {
    @TestSetup
    static void setup() {
        Doctor__c doctor = TestDataFactory.createDoctor();
        Patient__c patient = TestDataFactory.createPatient();
        TestDataFactory.createAppointment(doctor.Id, patient.Id, Date.today().addDays(1), '09:00 AM');
    }

    private static Appointment__c appointment() {
        return [SELECT Id, Patient__c FROM Appointment__c LIMIT 1];
    }

    @IsTest
    static void discountThenInsurance() {
        Test.startTest();
        BillingCalculator.BillBreakdown result = BillingCalculator.calculate(10000, 10, 20);
        Test.stopTest();

        Assert.areEqual(10000, result.grossAmount);
        Assert.areEqual(1000, result.discountAmount);
        Assert.areEqual(1800, result.insuranceAmount);
        Assert.areEqual(7200, result.amountDue);
    }

    @IsTest
    static void noDiscountOrInsurance() {
        Test.startTest();
        BillingCalculator.BillBreakdown result = BillingCalculator.calculate(5000, null, null);
        Test.stopTest();

        Assert.areEqual(0, result.insuranceAmount);
        Assert.areEqual(5000, result.amountDue);
    }

    @IsTest
    static void maxDiscountIsCappedAt100Percent() {
        Test.startTest();
        BillingCalculator.BillBreakdown full = BillingCalculator.calculate(5000, 100, 50);
        BillingCalculator.BillBreakdown over = BillingCalculator.calculate(5000, 150, 0);
        Test.stopTest();

        Assert.areEqual(0, full.amountDue);
        Assert.areEqual(0, full.insuranceAmount);
        Assert.areEqual(0, over.amountDue, 'Discount above 100% is capped');
    }

    @IsTest
    static void fullInsuranceAndNegativePercentages() {
        Test.startTest();
        BillingCalculator.BillBreakdown insured = BillingCalculator.calculate(8000, 0, 100);
        BillingCalculator.BillBreakdown negative = BillingCalculator.calculate(8000, -10, -5);
        Test.stopTest();

        Assert.areEqual(0, insured.amountDue);
        Assert.areEqual(8000, insured.insuranceAmount);
        Assert.areEqual(8000, negative.amountDue, 'Negative percentages are treated as zero');
    }

    @IsTest
    static void negativeChargesRejected() {
        Test.startTest();
        try {
            BillingCalculator.calculate(-1, 0, 0);
            Assert.fail('Expected HospitalException');
        } catch (HospitalException e) {
            Assert.areEqual('Charges cannot be negative.', e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void zeroProcedures() {
        Test.startTest();
        BillingCalculator.BillBreakdown empty = BillingCalculator.calculateForProcedures(new List<Id>(), 10, 20);
        BillingCalculator.BillBreakdown nullList = BillingCalculator.calculateForProcedures(null, 10, 20);
        Test.stopTest();

        Assert.areEqual(0, empty.amountDue);
        Assert.areEqual(0, nullList.grossAmount);
    }

    @IsTest
    static void multipleProceduresIncludingRepeats() {
        Procedure__c xray = TestDataFactory.createProcedure(1000);
        Procedure__c mri = TestDataFactory.createProcedure(4000);

        Test.startTest();
        BillingCalculator.BillBreakdown result = BillingCalculator.calculateForProcedures(new List<Id>{ xray.Id, mri.Id, xray.Id }, 0, 0);
        Test.stopTest();

        Assert.areEqual(6000, result.grossAmount);
    }

    @IsTest
    static void triggerPricesBillOnInsertAndRollsUpToPatient() {
        Appointment__c appointment = appointment();
        Procedure__c procedure = TestDataFactory.createProcedure(10000);

        Test.startTest();
        Billing__c bill = TestDataFactory.createBilling(null, procedure.Id, appointment.Id);
        Test.stopTest();

        Billing__c saved = [SELECT Patient__c, Patient_Email__c, Total_Charges__c, Insurance_Amount__c, Amount_Due__c FROM Billing__c WHERE Id = :bill.Id];
        Assert.areEqual(appointment.Patient__c, saved.Patient__c, 'Patient defaulted from the appointment');
        Assert.isNotNull(saved.Patient_Email__c);
        Assert.areEqual(10000, saved.Total_Charges__c);
        Assert.areEqual(1800, saved.Insurance_Amount__c);
        Assert.areEqual(7200, saved.Amount_Due__c);
        Assert.areEqual(7200, [SELECT Total_Billed_Amount__c FROM Patient__c WHERE Id = :appointment.Patient__c].Total_Billed_Amount__c);
    }

    @IsTest
    static void triggerRepricesOnUpdateAndDeleteResetsRollup() {
        Appointment__c appointment = appointment();
        Procedure__c procedure = TestDataFactory.createProcedure(10000);
        Billing__c bill = TestDataFactory.createBilling(appointment.Patient__c, procedure.Id, appointment.Id);

        Test.startTest();
        // Fresh sObject: the master-detail Appointment__c is not reparentable, so it must not be re-sent on update.
        update new Billing__c(Id = bill.Id, Discount__c = 0, Insurance_Coverage__c = 0);
        Assert.areEqual(10000, [SELECT Amount_Due__c FROM Billing__c WHERE Id = :bill.Id].Amount_Due__c);

        delete bill;
        Assert.areEqual(0, [SELECT Total_Billed_Amount__c FROM Patient__c WHERE Id = :appointment.Patient__c].Total_Billed_Amount__c);

        undelete bill;
        Test.stopTest();

        Assert.areEqual(10000, [SELECT Total_Billed_Amount__c FROM Patient__c WHERE Id = :appointment.Patient__c].Total_Billed_Amount__c);
    }

    @IsTest
    static void manualChargesWithoutProcedure() {
        Appointment__c appointment = appointment();
        Billing__c bill = new Billing__c(Appointment__c = appointment.Id, Total_Charges__c = 2000, Discount__c = 50);

        Test.startTest();
        insert bill;
        Test.stopTest();

        Assert.areEqual(1000, [SELECT Amount_Due__c FROM Billing__c WHERE Id = :bill.Id].Amount_Due__c);
    }

    @IsTest
    static void approvedInsuredBillSendsClaim() {
        Test.setMock(HttpCalloutMock.class, new HmsHttpCalloutMock(200, '{"claimId":"CLM-1"}'));
        Appointment__c appointment = appointment();
        Billing__c bill = TestDataFactory.createBilling(appointment.Patient__c, TestDataFactory.createProcedure(1000).Id, appointment.Id);

        Test.startTest();
        update new Billing__c(Id = bill.Id, Insurance__c = true, Status__c = 'Approved');
        Test.stopTest();

        Assert.areEqual(1, HmsHttpCalloutMock.requests.size(), 'One claim callout');
        Assert.isTrue(HmsHttpCalloutMock.requests[0].getEndpoint().startsWith('callout:Insurance_NC'));
    }
}
