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
  @track objectFields = [];
  @track error;
  @track isLoading = false;
  @track csvData;
  fieldMapping = {};

  handleUploadFinished(event) {
    const contentDocumentId = event.detail.files[0].documentId;
    this.readFile(contentDocumentId);
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
    this.fieldMapping[selectedColumn] = fieldApiName;
  }

  handleImportData() {
    if (!this.selectedObject || !this.csvData || Object.keys(this.fieldMapping).length === 0) {
      this.error = 'Por favor complete el mapeo de campos antes de importar';
      return;
    }

    this.isLoading = true;

    // Logging para diagnóstico
    console.log('Selected Object:', this.selectedObject);
    console.log('CSV Data:', this.csvData);
    console.log('Field Mapping:', this.fieldMapping);

    // Invertir el mapping para que sea header:fieldApiName
    const invertedMapping = {};
    Object.entries(this.fieldMapping).forEach(([column, field]) => {
      invertedMapping[column] = field;
    });

    console.log('Inverted Mapping:', invertedMapping);

    // Preparar los datos para la importación
    const importParams = {
      headers: this.csvData.headers,
      lines: this.csvData.lines
    };

    console.log('Import Params:', importParams);

    // Llamar al método de Apex para procesar la importación
    processDataImport({
      csvData: JSON.stringify(importParams),
      objectName: this.selectedObject,
      fieldMapping: invertedMapping
    })
      .then(result => {
        // Mostrar mensaje de éxito
        const evt = new ShowToastEvent({
          title: 'Éxito',
          message: result,
          variant: 'success'
        });
        this.dispatchEvent(evt);

        // Limpiar el formulario
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
    this.fieldMapping = {};
    this.selectedObject = null;
    this.fieldList = [];
    this.columnHeaders = [];
    this.error = null;

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

}