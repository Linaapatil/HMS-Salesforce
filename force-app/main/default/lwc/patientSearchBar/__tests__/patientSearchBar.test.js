import { createElement } from '@lwc/engine-dom';
import PatientSearchBar, { DEBOUNCE_MS } from 'c/patientSearchBar';
import searchPatients from '@salesforce/apex/PatientService.searchPatients';
import { publish } from 'lightning/messageService';
import PATIENT_SELECTED from '@salesforce/messageChannel/Patient_Selected__c';

jest.mock(
    '@salesforce/apex/PatientService.searchPatients',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

const PATIENTS = [
    { Id: 'a01000000000001AAA', Name: 'PAT-0001', Full_Name__c: 'Ananya Sharma', Age__c: 34, Blood_Group__c: 'O+' },
    { Id: 'a01000000000002AAA', Name: 'PAT-0002', Full_Name__c: 'Arjun Mehta', Age__c: 52, Blood_Group__c: 'B+' }
];

const flushPromises = () => new Promise((resolve) => process.nextTick(resolve));

function createComponent() {
    const element = createElement('c-patient-search-bar', { is: PatientSearchBar });
    document.body.appendChild(element);
    return element;
}

function typeSearch(element, value) {
    const input = element.shadowRoot.querySelector('lightning-input');
    input.value = value;
    input.dispatchEvent(new CustomEvent('change'));
}

describe('c-patient-search-bar', () => {
    beforeEach(() => {
        // Fake only the debounce timer; flushPromises relies on the real process.nextTick.
        jest.useFakeTimers({ doNotFake: ['nextTick', 'setImmediate'] });
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
        jest.useRealTimers();
    });

    it('debounces typing into a single Apex call and renders results', async () => {
        searchPatients.mockResolvedValue(PATIENTS);
        const element = createComponent();
        const resultsHandler = jest.fn();
        element.addEventListener('searchresults', resultsHandler);

        typeSearch(element, 'An');
        typeSearch(element, 'Ana');
        typeSearch(element, 'Anan');
        expect(searchPatients).not.toHaveBeenCalled();

        jest.advanceTimersByTime(DEBOUNCE_MS);
        await flushPromises();

        expect(searchPatients).toHaveBeenCalledTimes(1);
        expect(searchPatients).toHaveBeenCalledWith({ searchTerm: 'Anan' });

        const rows = element.shadowRoot.querySelectorAll('.patient-result');
        expect(rows).toHaveLength(2);
        expect(rows[0].querySelector('.patient-name').textContent).toBe('Ananya Sharma');
        expect(rows[0].querySelector('.patient-id').textContent).toBe('PAT-0001 · 34 yrs · O+');
        expect(resultsHandler).toHaveBeenCalledTimes(1);
        expect(resultsHandler.mock.calls[0][0].detail).toEqual(PATIENTS);
    });

    it('does not call Apex for search terms shorter than two characters', async () => {
        const element = createComponent();

        typeSearch(element, 'A');
        jest.advanceTimersByTime(DEBOUNCE_MS);
        await flushPromises();

        expect(searchPatients).not.toHaveBeenCalled();
        expect(element.shadowRoot.querySelector('.patient-result')).toBeNull();
    });

    it('shows the empty state when nothing matches', async () => {
        searchPatients.mockResolvedValue([]);
        const element = createComponent();

        typeSearch(element, 'zzz');
        jest.advanceTimersByTime(DEBOUNCE_MS);
        await flushPromises();

        expect(element.shadowRoot.querySelector('.empty-state h3').textContent).toBe('No patient found');
    });

    it('shows an error when the search fails', async () => {
        searchPatients.mockRejectedValue({ body: { message: 'boom' } });
        const element = createComponent();

        typeSearch(element, 'Ananya');
        jest.advanceTimersByTime(DEBOUNCE_MS);
        await flushPromises();

        expect(element.shadowRoot.querySelector('.error-message')).not.toBeNull();
        expect(element.shadowRoot.querySelector('.patient-result')).toBeNull();
    });

    it('publishes PATIENT_SELECTED and fires patientselected when a patient is clicked', async () => {
        searchPatients.mockResolvedValue(PATIENTS);
        const element = createComponent();
        const selectedHandler = jest.fn();
        element.addEventListener('patientselected', selectedHandler);

        typeSearch(element, 'Ananya');
        jest.advanceTimersByTime(DEBOUNCE_MS);
        await flushPromises();

        element.shadowRoot.querySelector('.patient-result').click();
        await flushPromises();

        expect(publish).toHaveBeenCalledWith(undefined, PATIENT_SELECTED, { patientId: PATIENTS[0].Id });
        expect(selectedHandler.mock.calls[0][0].detail).toBe(PATIENTS[0].Id);
        expect(element.shadowRoot.querySelector('.patient-result').className).toContain('selected');
    });
});
