trigger AppointmentTrigger on Appointment__c(
    before insert,
    before update,
    after insert,
    after update,
    after delete,
    after undelete
) {
    AppointmentTriggerHandler handler = new AppointmentTriggerHandler();

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
            handler.afterUndelete(Trigger.new);
        }
    }
}
