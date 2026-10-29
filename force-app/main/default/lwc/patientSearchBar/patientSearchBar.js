import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { publish, MessageContext } from 'lightning/messageService';
import searchPatients from '@salesforce/apex/PatientService.searchPatients';
import PATIENT_SELECTED from '@salesforce/messageChannel/Patient_Selected__c';

export const DEBOUNCE_MS = 300;
const MIN_SEARCH_LENGTH = 2;

/**
 * Searches patients by name, Patient ID (PAT-0001) or record Id.
 * - Imperative Apex call (PatientService.searchPatients), debounced to avoid API spam
 * - Emits `searchresults` to the parent
 * - Selecting a patient publishes PATIENT_SELECTED (consumed by appointmentForm) and emits `patientselected`
 */
export default class PatientSearchBar extends NavigationMixin(LightningElement) {
    searchTerm = '';
    patients = [];
    selectedPatientId;
    error;
    isLoading = false;
    debounceTimeout;

    @wire(MessageContext)
    messageContext;

    get hasResults() {
        return this.patients.length > 0;
    }

    get showNoResults() {
        return !this.isLoading && !this.error && this.searchTerm.trim().length >= MIN_SEARCH_LENGTH && !this.hasResults;
    }

    get resultRows() {
        return this.patients.map((patient) => ({
            ...patient,
            displayName: patient.Full_Name__c || patient.Name,
            details: [patient.Name, patient.Age__c != null ? `${patient.Age__c} yrs` : null, patient.Blood_Group__c].filter(Boolean).join(' · '),
            cssClass: patient.Id === this.selectedPatientId ? 'patient-result selected' : 'patient-result'
        }));
    }

    disconnectedCallback() {
        clearTimeout(this.debounceTimeout);
    }

    handleSearch(event) {
        this.searchTerm = event.target.value || '';
        clearTimeout(this.debounceTimeout);

        if (this.searchTerm.trim().length < MIN_SEARCH_LENGTH) {
            this.patients = [];
            this.error = undefined;
            return;
        }

        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.debounceTimeout = setTimeout(() => this.runSearch(), DEBOUNCE_MS);
    }

    async runSearch() {
        this.isLoading = true;
        try {
            const result = await searchPatients({ searchTerm: this.searchTerm });
            this.patients = result || [];
            this.error = undefined;
            this.dispatchEvent(new CustomEvent('searchresults', { detail: this.patients }));
        } catch (error) {
            this.patients = [];
            this.error = error;
        } finally {
            this.isLoading = false;
        }
    }

    handlePatientClick(event) {
        const patientId = event.currentTarget.dataset.id;
        this.selectedPatientId = patientId;

        publish(this.messageContext, PATIENT_SELECTED, { patientId });
        this.dispatchEvent(new CustomEvent('patientselected', { detail: patientId }));
    }

    handleOpenPatient(event) {
        event.stopPropagation();
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: event.currentTarget.dataset.id,
                objectApiName: 'Patient__c',
                actionName: 'view'
            }
        });
    }

    handleNewPatient() {
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: { url: '/flow/New_Patient_Registration_Flow' }
        });
    }
}
