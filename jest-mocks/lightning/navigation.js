/*
 * Jest mock for lightning/navigation that records the last Navigate call,
 * so tests can assert on the page reference (pattern from the Salesforce LWC recipes).
 */
import { createTestWireAdapter } from '@salesforce/wire-service-jest-util';

export const CurrentPageReference = createTestWireAdapter(jest.fn());

let _pageReference;
let _replace;

const Navigate = Symbol('Navigate');
const GenerateUrl = Symbol('GenerateUrl');

export const NavigationMixin = (Base) => {
    return class extends Base {
        [Navigate](pageReference, replace) {
            _pageReference = pageReference;
            _replace = replace;
        }
        [GenerateUrl](pageReference) {
            _pageReference = pageReference;
            return Promise.resolve('https://www.example.com');
        }
    };
};
NavigationMixin.Navigate = Navigate;
NavigationMixin.GenerateUrl = GenerateUrl;

/** Returns the page reference (and replace flag) passed to the last Navigate call, then resets. */
export const getNavigateCalledWith = () => {
    const result = { pageReference: _pageReference, replace: _replace };
    _pageReference = undefined;
    _replace = undefined;
    return result;
};
