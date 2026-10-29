import { createElement } from '@lwc/engine-dom';
import AppointmentForm, { SPECIALIST_RECORD_TYPE } from 'c/appointmentForm';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { getRecord } from 'lightning/uiRecordApi';
import { publish, subscribe } from 'lightning/messageService';
import APPOINTMENT_REFRESH from '@salesforce/messageChannel/Appointment_Refresh__c';
import { getNavigateCalledWith } from 'lightning/navigation';

const OBJECT_INFO = {
    defaultRecordTypeId: '012000000000001AAA',
    recordTypeInfos: {
        '012000000000001AAA': { name: 'General Consultation', recordTypeId: '012000000000001AAA', available: true, master: false },
        '012000000000002AAA': { name: SPECIALIST_RECORD_TYPE, recordTypeId: '012000000000002AAA', available: true, master: false },
        '012000000000000AAA': { name: 'Master', recordTypeId: '012000000000000AAA', available: true, master: true }
    }
};

const doctorRecord = (status) => ({
    fields: {
        Name: { value: 'Dr. Meera Iyer' },
        Specialization__c: { value: 'Cardiology' },
        Status__c: { value: status },
        Availability__c: { value: 'Available' },
        Active_Appointments__c: { value: 3 }
    }
});

const flushPromises = () => new Promise((resolve) => process.nextTick(resolve));

function createComponent(props = {}) {
    const element = createElement('c-appointment-form', { is: AppointmentForm });
    Object.assign(element, props);
    document.body.appendChild(element);
    return element;
}

function chooseDoctor(element, doctorId) {
    const doctorField = [...element.shadowRoot.querySelectorAll('lightning-input-field')].find((f) => f.fieldName === 'Doctor__c');
    doctorField.dispatchEvent(new CustomEvent('change', { detail: { value: doctorId } }));
}

describe('c-appointment-form', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('loads record types (without Master) and defaults to the default record type', async () => {
        const element = createComponent();
        getObjectInfo.emit(OBJECT_INFO);
        await flushPromises();

        const combobox = element.shadowRoot.querySelector('lightning-combobox');
        expect(combobox.options.map((o) => o.label)).toEqual(['General Consultation', SPECIALIST_RECORD_TYPE]);
        expect(combobox.value).toBe('012000000000001AAA');
        expect(element.shadowRoot.querySelector('.specialist-section')).toBeNull();
    });

    it('shows specialist fields only for the Specialist Consultation record type', async () => {
        const element = createComponent();
        getObjectInfo.emit(OBJECT_INFO);
        await flushPromises();

        const combobox = element.shadowRoot.querySelector('lightning-combobox');
        combobox.dispatchEvent(new CustomEvent('change', { detail: { value: '012000000000002AAA' } }));
        await flushPromises();

        expect(element.shadowRoot.querySelector('.specialist-section')).not.toBeNull();
    });

    it('subscribes to PATIENT_SELECTED and pre-fills the patient', async () => {
        const element = createComponent();
        expect(subscribe).toHaveBeenCalled();

        const handler = subscribe.mock.calls[0][2];
        handler({ patientId: 'a01000000000001AAA' });
        await flushPromises();

        const patientField = [...element.shadowRoot.querySelectorAll('lightning-input-field')].find((f) => f.fieldName === 'Patient__c');
        expect(patientField.value).toBe('a01000000000001AAA');
    });

    it('shows the selected doctor from LDS and blocks booking when the doctor is on leave', async () => {
        const element = createComponent();
        chooseDoctor(element, 'a03000000000001AAA');
        getRecord.emit(doctorRecord('Inactive'));
        await flushPromises();

        expect(element.shadowRoot.querySelector('.doctor-name').textContent).toBe('Dr. Meera Iyer');
        expect(element.shadowRoot.querySelector('.doctor-status').textContent).toBe('On leave / inactive');
        expect(element.shadowRoot.querySelector('lightning-button').disabled).toBe(true);

        getRecord.emit(doctorRecord('Active'));
        await flushPromises();
        expect(element.shadowRoot.querySelector('lightning-button').disabled).toBe(false);
    });

    it('publishes a refresh, notifies the parent and navigates to the new record on success', async () => {
        const element = createComponent();
        const savedHandler = jest.fn();
        element.addEventListener('appointmentsaved', savedHandler);

        element.shadowRoot.querySelector('lightning-record-edit-form').dispatchEvent(new CustomEvent('success', { detail: { id: 'a02000000000001AAA' } }));
        await flushPromises();

        expect(publish).toHaveBeenCalledWith(undefined, APPOINTMENT_REFRESH, { appointmentId: 'a02000000000001AAA' });
        expect(savedHandler.mock.calls[0][0].detail).toBe('a02000000000001AAA');
        const { pageReference } = getNavigateCalledWith();
        expect(pageReference.type).toBe('standard__recordPage');
        expect(pageReference.attributes.recordId).toBe('a02000000000001AAA');
    });

    it('stays on the page when embedded with stay-on-page', async () => {
        const element = createComponent({ stayOnPage: true });
        const savedHandler = jest.fn();
        element.addEventListener('appointmentsaved', savedHandler);

        element.shadowRoot.querySelector('lightning-record-edit-form').dispatchEvent(new CustomEvent('success', { detail: { id: 'a02000000000003AAA' } }));
        await flushPromises();

        expect(savedHandler).toHaveBeenCalledTimes(1);
        expect(getNavigateCalledWith().pageReference).toBeUndefined();
    });
});
