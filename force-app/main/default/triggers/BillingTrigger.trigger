trigger BillingTrigger on Billing__c(
    before insert,
    before update,
    after insert,
    after update,
    after delete,
    after undelete
) {
    BillingTriggerHandler handler = new BillingTriggerHandler();

    switch on Trigger.operationType {
        when BEFORE_INSERT {
            handler.beforeInsert(Trigger.new);
        }
        when BEFORE_UPDATE {
            handler.beforeUpdate(Trigger.new, Trigger.oldMap);
        }
        when AFTER_INSERT {
            handler.afterInsert(Trigger.new);
        }
        when AFTER_UPDATE {
            handler.afterUpdate(Trigger.new, Trigger.oldMap);
        }
        when AFTER_DELETE {
            handler.afterDelete(Trigger.old);
        }
        when AFTER_UNDELETE {
            handler.afterInsert(Trigger.new);
        }
    }
}
