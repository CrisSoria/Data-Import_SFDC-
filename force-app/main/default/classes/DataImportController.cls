public with sharing class DataImportController {
    
    /**
     * Método para validar el archivo CSV antes de la importación
     * Verifica el formato y estructura del archivo
     * @param fileContent - Contenido del archivo en formato Base64
     * @param objectName - Nombre de la API del objeto donde se importarán los datos
     * @return Map<String, Object> - Retorna un mapa con la información de validación
     */
    @AuraEnabled
    public static Map<String, Object> validateCSVFile(String fileContent, String objectName) {
        try {
            Map<String, Object> result = new Map<String, Object>();
            if (String.isBlank(fileContent)) {
                throw new CustomException('El archivo está vacío');
            }
            
            // Decodificar el contenido del archivo
            String csvContent = EncodingUtil.base64Decode(fileContent).toString();
            List<String> csvLines = csvContent.split('\n');
            
            if (csvLines.isEmpty()) {
                throw new CustomException('El archivo no contiene datos');
            }
            
            // Validar headers
            List<String> headers = csvLines[0].split(',');
            validateHeaders(headers, objectName);
            
            result.put('success', true);
            result.put('headers', headers);
            result.put('totalRows', csvLines.size() - 1);
            
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    /**
     * Método para procesar la importación de datos
     * @param fileContent - Contenido del archivo en formato Base64
     * @param objectName - Nombre de la API del objeto destino
     * @param fieldMapping - Mapeo de campos CSV a campos de Salesforce
     * @return String - ID del job de importación
     */
    @AuraEnabled
    public static String processDataImport(String fileContent, String objectName, Map<String, String> fieldMapping) {
        try {
            // Decodificar el contenido
            String csvContent = EncodingUtil.base64Decode(fileContent).toString();
            List<String> csvLines = csvContent.split('\n');
            
            // Obtener headers y registros
            List<String> headers = csvLines[0].split(',');
            List<SObject> recordsToInsert = new List<SObject>();
            
            // Procesar cada línea del CSV
            for (Integer i = 1; i < csvLines.size(); i++) {
                List<String> values = csvLines[i].split(',');
                SObject record = createRecord(objectName, headers, values, fieldMapping);
                if (record != null) {
                    recordsToInsert.add(record);
                }
            }
            
            // Insertar registros en lotes
            if (!recordsToInsert.isEmpty()) {
                Database.SaveResult[] results = Database.insert(recordsToInsert, false);
                processResults(results);
            }
            
            return 'Success';
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    /**
     * Método para obtener los campos disponibles de un objeto
     * @param objectName - Nombre de la API del objeto
     * @return List<Map<String, String>> - Lista de campos disponibles con su tipo
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getObjectFields(String objectName) {
        try {
            List<Map<String, String>> fields = new List<Map<String, String>>();
            
            // Obtener el esquema del objeto
            Schema.SObjectType targetType = Schema.getGlobalDescribe().get(objectName);
            if (targetType == null) {
                throw new CustomException('Objeto no encontrado: ' + objectName);
            }
            
            Map<String, Schema.SObjectField> fieldMap = targetType.getDescribe().fields.getMap();
            
            // Procesar cada campo
            for (String fieldName : fieldMap.keySet()) {
                Schema.DescribeFieldResult field = fieldMap.get(fieldName).getDescribe();
                if (field.isCreateable()) {
                    Map<String, String> fieldInfo = new Map<String, String>{
                        'label' => field.getLabel(),
                        'apiName' => field.getName(),
                        'type' => String.valueOf(field.getType())
                    };
                    fields.add(fieldInfo);
                }
            }
            
            return fields;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    /**
     * Método privado para validar los headers del CSV
     * @param headers - Lista de headers del CSV
     * @param objectName - Nombre del objeto
     */
    private static void validateHeaders(List<String> headers, String objectName) {
        if (headers == null || headers.isEmpty()) {
            throw new CustomException('Headers no válidos en el archivo CSV');
        }
        
        // Validar que los headers no estén vacíos
        for (String header : headers) {
            if (String.isBlank(header)) {
                throw new CustomException('Se encontró un header vacío en el CSV');
            }
        }
    }
    
    /**
     * Método privado para crear un registro a partir de los valores del CSV
     * @param objectName - Nombre del objeto
     * @param headers - Headers del CSV
     * @param values - Valores de la fila
     * @param fieldMapping - Mapeo de campos
     * @return SObject - Registro creado
     */
    private static SObject createRecord(String objectName, List<String> headers, List<String> values, Map<String, String> fieldMapping) {
        SObject record = Schema.getGlobalDescribe().get(objectName).newSObject();
        
        for (Integer i = 0; i < headers.size() && i < values.size(); i++) {
            String fieldName = fieldMapping.get(headers[i]);
            if (String.isNotBlank(fieldName) && String.isNotBlank(values[i])) {
                record.put(fieldName, values[i]);
            }
        }
        
        return record;
    }
    
    /**
     * Método privado para procesar los resultados de la inserción
     * @param results - Resultados de la operación DML
     */
    private static void processResults(Database.SaveResult[] results) {
        List<String> errors = new List<String>();
        
        for (Database.SaveResult result : results) {
            if (!result.isSuccess()) {
                for (Database.Error error : result.getErrors()) {
                    errors.add(error.getMessage());
                }
            }
        }
        
        if (!errors.isEmpty()) {
            throw new CustomException(String.join(errors, '\n'));
        }
    }
    
    /**
     * Clase personalizada para manejo de excepciones
     */
    public class CustomException extends Exception {}
}