import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import loadCSVdata from '@salesforce/apex/DataImportController.loadCSVdata';
import getCreatableObjects from '@salesforce/apex/DataImportController.getCreatableObjects';
import getObjectFields from '@salesforce/apex/DataImportController.getObjectFields';
import processDataImport from '@salesforce/apex/DataImportController.processDataImport';

export default class DataImportWizard extends LightningElement {
  acceptedFormats = ['.csv'];
  salesforceObjects = [];
  @track fieldList = [];
  @track columnHeaders = [];
  @track selectedObject;
  @track error;
  @track isLoading = false;
  @track csvData;
  @track currentStep = 'upload'; // Posibles valores: 'upload', 'mapping', 'import'
  @track fieldMapping = {};

  // Computed properties
  get mappedFieldsCount() {
    return Object.keys(this.fieldMapping).length;
  }

  get isImportDisabled() {
    return !this.selectedObject ||
      !this.csvData ||
      this.mappedFieldsCount === 0 ||
      this.isLoading;
  }

  // Getter para la lista de campos con su estado de mapeo
  get fieldListWithStatus() {
    return this.fieldList.map(field => {
      const mappedValue = this.fieldMapping[field.apiName] || '';
      const isMapped = Boolean(mappedValue);
      return {
        ...field,
        mappedValue,
        isMapped,
        cssClass: `field-mapping-item ${isMapped ? 'slds-has-success' : ''}`
      };
    });
  }
  getFieldMappingClass(apiName) {
    const baseClasses = 'field-mapping-item';
    return this.fieldMapping[apiName]
      ? `${baseClasses} slds-has-success`
      : baseClasses;
  }

  getFieldMappingValue(apiName) {
    return this.fieldMapping[apiName] || '';
  }

  handleUploadFinished(event) {
    const contentDocumentId = event.detail.files[0].documentId;
    this.readFile(contentDocumentId);
    this.updatePathStatus('mapping');
  }

  async readFile(Id) {
    try {
      this.isLoading = true;
      const csvData = await loadCSVdata({ documentId: Id });
      this.csvData = csvData;
      // Preparar las opciones para el combobox de columnas
      if (csvData.headers) {
        this.columnHeaders = csvData.headers.map(header => ({
          label: header,
          value: header
        }));
      }
      await this.fetchObjects();
      this.error = undefined;
    } catch (error) {
      console.error("Error procesando el archivo:", error);
      this.error = error.body?.message || 'Error procesando el archivo';
    } finally {
      this.isLoading = false;
    }
  }

  async fetchObjects() {
    try {
      const objectsNameLabel = await getCreatableObjects();
      this.salesforceObjects = objectsNameLabel.map(obj => ({
        label: obj.label,
        value: obj.apiName
      }));
    } catch (error) {
      this.error = error.body?.message || 'Error al obtener los objetos';
      console.error("Error obteniendo objetos:", error);
    }
  }

  async handleObjectSelection(event) {
    try {
      this.isLoading = true;
      this.selectedObject = event.detail.value;
      this.error = undefined;
      await this.loadFields();
    } catch (error) {
      this.error = error.body?.message || 'Error al seleccionar el objeto';
      console.error("Error en la selección del objeto:", error);
    } finally {
      this.isLoading = false;
    }
  }

  async loadFields() {
    try {
      const fields = await getObjectFields({ objectName: this.selectedObject });
      this.fieldList = fields;
      this.error = undefined;
    } catch (error) {
      this.error = error.body?.message || 'Error al cargar los campos';
      this.fieldList = [];
      console.error("Error cargando campos:", error);
    }
  }

  handleColumnSelection(event) {
    const selectedColumn = event.detail.value;
    const fieldApiName = event.target.dataset.apiname;

    if (selectedColumn) {
      this.fieldMapping = {
        ...this.fieldMapping,
        [fieldApiName]: selectedColumn
      };
    } else {
      const newMapping = { ...this.fieldMapping };
      delete newMapping[fieldApiName];
      this.fieldMapping = newMapping;
    }

    console.log('Field Mapping Updated:', this.fieldMapping);
    console.log('Mapped Fields Count:', this.mappedFieldsCount);
  }


  handleImportData() {
    if (this.isImportDisabled) {
      this.error = 'Por favor complete el mapeo de campos antes de importar';
      return;
    }

    this.isLoading = true;
    console.log('Selected Object:', this.selectedObject);
    console.log('CSV Data:', this.csvData);
    console.log('Field Mapping:', this.fieldMapping);

    // Invertir el mapping para que sea header:fieldApiName
    const invertedMapping = {};
    Object.entries(this.fieldMapping).forEach(([field, column]) => {
      invertedMapping[column] = field;
    });

    // Preparar los datos para la importación
    const importParams = {
      headers: this.csvData.headers,
      lines: this.csvData.lines
    };

    processDataImport({
      csvData: JSON.stringify(importParams),
      objectName: this.selectedObject,
      fieldMapping: invertedMapping
    })
      .then(result => {
        const evt = new ShowToastEvent({
          title: 'Éxito',
          message: result,
          variant: 'success'
        });
        this.dispatchEvent(evt);
        this.resetForm();
      })
      .catch(error => {
        console.error('Error importing data:', error);
        this.error = error.body?.message || 'Error al importar los datos';
      })
      .finally(() => {
        this.isLoading = false;
      });
  }

  resetForm() {
    this.csvData = null;
    this.fieldMapping = {};  // Reseteamos con un nuevo objeto vacío
    this.selectedObject = null;
    this.fieldList = [];
    this.columnHeaders = [];
    this.error = null;
    this.currentStep = 'upload';
    this.updatePathStatus('upload');

    // Limpiar los componentes del formulario
    const fileUpload = this.template.querySelector('lightning-file-upload');
    if (fileUpload) {
      fileUpload.value = null;
    }

    const objectCombobox = this.template.querySelector('lightning-combobox[name="objectselected"]');
    if (objectCombobox) {
      objectCombobox.value = null;
    }
  }

  updatePathStatus(step) {
    const steps = ['upload', 'mapping', 'import'];
    const pathItems = this.template.querySelectorAll('.slds-path__item');

    steps.forEach((stepName, index) => {
      if (pathItems[index]) {
        pathItems[index].classList.remove('slds-is-active', 'slds-is-complete');
        if (stepName === step) {
          pathItems[index].classList.add('slds-is-active');
        } else if (steps.indexOf(stepName) < steps.indexOf(step)) {
          pathItems[index].classList.add('slds-is-complete');
        }
      }
    });
  }

}