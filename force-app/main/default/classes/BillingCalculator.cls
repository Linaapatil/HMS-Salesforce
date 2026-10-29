/**
 * Calculates bill totals from procedures, discounts and insurance coverage.
 *
 * Discount__c and Insurance_Coverage__c are percentages (0-100). Discount is applied
 * first, insurance then covers its share of the discounted amount:
 *   gross     = procedure price (or Total_Charges__c when no procedure is set)
 *   net       = gross - gross * discount%
 *   insurance = net * coverage%
 *   amountDue = net - insurance
 */
public with sharing class BillingCalculator {
    public static final Decimal MAX_PERCENT = 100;

    /** Fills Total_Charges__c, Insurance_Amount__c and Amount_Due__c on the given (unsaved or before-trigger) bills. */
    public static void calculateBills(List<Billing__c> bills) {
        Set<Id> procedureIds = new Set<Id>();

        for (Billing__c bill : bills) {
            if (bill.Procedure__c != null) {
                procedureIds.add(bill.Procedure__c);
            }
        }

        Map<Id, Procedure__c> procedures = procedureIds.isEmpty()
            ? new Map<Id, Procedure__c>()
            : new Map<Id, Procedure__c>([SELECT Id, Price__c, Base_Charge__c FROM Procedure__c WHERE Id IN :procedureIds]);

        for (Billing__c bill : bills) {
            Decimal gross = bill.Total_Charges__c;
            Procedure__c procedure = procedures.get(bill.Procedure__c);

            if (procedure != null) {
                gross = procedure.Price__c != null ? procedure.Price__c : procedure.Base_Charge__c;
            }
            if (gross == null) {
                // Nothing to price (e.g. a default charge set directly on Amount_Due__c by a flow).
                continue;
            }

            BillBreakdown breakdown = calculate(gross, bill.Discount__c, bill.Insurance_Coverage__c);
            bill.Total_Charges__c = breakdown.grossAmount;
            bill.Insurance_Amount__c = breakdown.insuranceAmount;
            bill.Amount_Due__c = breakdown.amountDue;
        }
    }

    /** Sums the prices of several procedures (e.g. all procedures done in one visit) and prices them as one bill. */
    public static BillBreakdown calculateForProcedures(List<Id> procedureIds, Decimal discountPercent, Decimal insurancePercent) {
        Decimal gross = 0;

        if (procedureIds != null && !procedureIds.isEmpty()) {
            Map<Id, Procedure__c> procedures = new Map<Id, Procedure__c>(
                [SELECT Id, Price__c, Base_Charge__c FROM Procedure__c WHERE Id IN :procedureIds]
            );
            // Iterate the input list so the same procedure performed twice is charged twice.
            for (Id procedureId : procedureIds) {
                Procedure__c procedure = procedures.get(procedureId);
                if (procedure != null) {
                    gross += procedure.Price__c != null ? procedure.Price__c : nullToZero(procedure.Base_Charge__c);
                }
            }
        }

        return calculate(gross, discountPercent, insurancePercent);
    }

    public static BillBreakdown calculate(Decimal grossAmount, Decimal discountPercent, Decimal insurancePercent) {
        Decimal gross = nullToZero(grossAmount);
        if (gross < 0) {
            throw new HospitalException('Charges cannot be negative.');
        }

        Decimal discount = clampPercent(discountPercent);
        Decimal coverage = clampPercent(insurancePercent);

        BillBreakdown result = new BillBreakdown();
        result.grossAmount = gross;
        result.discountAmount = (gross * discount / 100).setScale(2);
        Decimal net = gross - result.discountAmount;
        result.insuranceAmount = (net * coverage / 100).setScale(2);
        result.amountDue = net - result.insuranceAmount;
        return result;
    }

    private static Decimal clampPercent(Decimal value) {
        if (value == null || value < 0) {
            return 0;
        }
        return value > MAX_PERCENT ? MAX_PERCENT : value;
    }

    private static Decimal nullToZero(Decimal value) {
        return value == null ? 0 : value;
    }

    public class BillBreakdown {
        @AuraEnabled
        public Decimal grossAmount;
        @AuraEnabled
        public Decimal discountAmount;
        @AuraEnabled
        public Decimal insuranceAmount;
        @AuraEnabled
        public Decimal amountDue;
    }
}
