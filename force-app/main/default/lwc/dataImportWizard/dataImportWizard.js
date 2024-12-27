import { LightningElement } from 'lwc';

export default class DataImportWizard extends LightningElement {
  acceptedFormats = ['.csv'];
  salesforceObjects = [];
  fieldList = [];
  columnHeaders = [];

  handleUploadFinished(event) {
    // Get the list of uploaded files
    const uploadedFiles = event.detail.files;
    alert('No. of files uploaded : ' + uploadedFiles.length);
  }

  handleObjectSelection(event) {

  }

  handleColumnSelection(event) {

  }

  handleImportData(event) {

  }
}