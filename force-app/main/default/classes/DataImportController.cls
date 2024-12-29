public with sharing class DataImportController {
	public class SObjectDescribe {
		@AuraEnabled
		public String label { get; set; }
		@AuraEnabled
		public String apiName { get; set; }

		public SObjectDescribe(String label, String name) {
			this.label = label;
			this.apiName = name;
		}
	}
	/**
	 * Método para obtener el archivo CSV cargado
	 * Verifica el formato y estructura del archivo
	 * @param documentId - Id generado por ContentVersion al subir el archivo
	 * @return List<String> - Retorna una lista con la información del CSV
	 */
	@AuraEnabled
	public static Map<String, Object> loadCSVdata(String documentId) {
		try {
			// Validamos el input
			if (String.isEmpty(documentId)) {
				throw new CustomException('Document ID no puede ser nulo o vacío');
			}

			ContentVersion contentVersionObj = [
				SELECT Id, VersionData
				FROM ContentVersion
				WHERE ContentDocumentId = :documentId
				LIMIT 1
			];

			Blob versionDataBlob = contentVersionObj.VersionData;
			if (versionDataBlob == null) {
				throw new CustomException('El contenido del archivo es nulo');
			}

			String csvContent;
			try {
				// Limpiamos los caracteres especiales al convertir el blob
				csvContent = cleanCSVContent(versionDataBlob.toString());
			} catch (Exception e) {
				throw new CustomException(
					'Error al convertir el archivo: ' + e.getMessage()
				);
			}

			return validateCSVFile(csvContent);
		} catch (CustomException e) {
			System.debug('Error personalizado: ' + e.getMessage());
			throw new AuraHandledException(e.getMessage());
		} catch (Exception e) {
			System.debug('Error inesperado en la línea N°: ' + e.getLineNumber());
			System.debug('Error a causa de: ' + e.getCause());
			System.debug('Error message: ' + e.getMessage());
			throw new AuraHandledException('Error inesperado: ' + e.getMessage());
		}
	}

	/**
	 * Método para limpiar el contenido del CSV de caracteres especiales
	 * @param content - Contenido original del CSV
	 * @return String - Contenido limpio
	 */
	private static String cleanCSVContent(String content) {
		if (String.isBlank(content))
			return '';

		// Normalizar saltos de línea
		content = content.replace('\r\n', '\n');
		content = content.replace('\r', '\n');

		// Dividir en líneas y limpiar cada línea
		List<String> lines = content.split('\n');
		for (Integer i = 0; i < lines.size(); i++) {
			// Remover espacios en blanco al inicio y final, y cualquier \r remanente
			lines[i] = lines[i].trim().replace('\r', '');
		}

		// Reconstruir el contenido
		return String.join(lines, '\n');
	}

	/**
	 * Método privado para validar el archivo CSV antes de la importación
	 * Verifica el formato y estructura del archivo
	 * @param fileContent - Contenido del archivo en formato String
	 * @return Map<String, Object> - Retorna un mapa con la información de validación
	 */
	private static Map<String, Object> validateCSVFile(String fileContent) {
		Map<String, Object> result = new Map<String, Object>();

		if (String.isBlank(fileContent)) {
			throw new CustomException('El archivo está vacío');
		}

		List<String> csvLines = fileContent.split('\n');
		if (csvLines.isEmpty()) {
			throw new CustomException('El archivo no contiene datos');
		}

		// Limpiar headers individualmente
		List<String> headers = new List<String>();
		for (String header : csvLines.remove(0).split(',')) {
			headers.add(header.trim());
		}

		validateHeaders(headers);

		result.put('success', true);
		result.put('headers', headers);
		result.put('lines', csvLines);
		result.put('totalRows', csvLines.size());

		return result;
	}

	/**
	 * Método privado para validar los headers del CSV
	 * @param headers - Lista de headers del CSV
	 */
	private static void validateHeaders(List<String> headers) {
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
	 * Método para obtener todos los objetos que el usuario puede crear
	 * @return List - Con label y name de objetos
	 */
	@AuraEnabled
	public static List<SObjectDescribe> getCreatableObjects() {
		try {
			List<SObjectDescribe> creatableObjects = new List<SObjectDescribe>();

			for (
				Schema.SObjectType objectType : Schema.getGlobalDescribe().values()
			) {
				Schema.DescribeSObjectResult describeResult = objectType.getDescribe();
				if (
					describeResult.isCreateable() && !describeResult.isCustomSetting()
				) {
					creatableObjects.add(
						new SObjectDescribe(
							describeResult.getLabel(),
							describeResult.getName()
						)
					);
				}
			}
			return creatableObjects;
		} catch (Exception e) {
			throw new AuraHandledException(e.getMessage());
		}
	}

	/**
	 * Método para procesar la importación de datos
	 * @param fileContent - Contenido del archivo CSV
	 * @param objectName - Nombre de la API del objeto destino
	 * @param fieldMapping - Mapeo de campos CSV a campos de Salesforce
	 * @return String - ID del job de importación
	 */
	@AuraEnabled
	public static String processDataImport(
		String csvData,
		String objectName,
		Map<String, String> fieldMapping
	) {
		try {
			// Deserializar los datos del CSV
			Map<String, Object> csvDataMap = (Map<String, Object>) JSON.deserializeUntyped(
				csvData
			);

			List<Object> headersObj = (List<Object>) csvDataMap.get('headers');
			List<Object> linesObj = (List<Object>) csvDataMap.get('lines');

			List<String> headers = new List<String>();
			for (Object header : headersObj) {
				headers.add(String.valueOf(header));
			}

			List<String> lines = new List<String>();
			for (Object line : linesObj) {
				lines.add(String.valueOf(line));
			}

			// Obtener el tipo de objeto y sus campos
			Schema.SObjectType targetType = Schema.getGlobalDescribe()
				.get(objectName);
			Map<String, Schema.SObjectField> fieldMap = targetType.getDescribe()
				.fields.getMap();

			List<SObject> recordsToInsert = new List<SObject>();

			// Procesar cada línea del CSV
			for (String line : lines) {
				if (String.isBlank(line))
					continue;

				// Parsear la línea del CSV considerando comillas
				List<String> values = parseCSVLine(line);

				if (values.size() != headers.size()) {
					System.debug(
						'Skipping line due to size mismatch. Headers: ' +
							headers.size() +
							', Values: ' +
							values.size()
					);
					continue;
				}

				SObject newRecord = targetType.newSObject();
				Boolean hasValidFields = false;

				for (Integer i = 0; i < headers.size(); i++) {
					String header = headers[i];
					String fieldApiName = fieldMapping.get(header);

					if (String.isNotBlank(fieldApiName) && i < values.size()) {
						String value = values[i].trim();
						// Remover comillas extras si existen
						if (value.startsWith('"') && value.endsWith('"')) {
							value = value.substring(1, value.length() - 1);
						}

						if (String.isNotBlank(value)) {
							Schema.SObjectField field = fieldMap.get(fieldApiName);
							if (field != null) {
								Object convertedValue = convertValue(
									value,
									field.getDescribe()
								);
								if (convertedValue != null) {
									newRecord.put(fieldApiName, convertedValue);
									hasValidFields = true;
								}
							}
						}
					}
				}

				if (hasValidFields) {
					recordsToInsert.add(newRecord);
				}
			}

			System.debug('Records to insert: ' + recordsToInsert);

			// Realizar la inserción
			List<Database.SaveResult> results = new List<Database.SaveResult>();
			if (!recordsToInsert.isEmpty()) {
				results = Database.insert(recordsToInsert, false);
			}

			// Procesar resultados
			Integer successCount = 0;
			List<String> errors = new List<String>();

			for (Database.SaveResult result : results) {
				if (result.isSuccess()) {
					successCount++;
				} else {
					errors.add(String.join(result.getErrors(), ', '));
				}
			}

			if (!errors.isEmpty()) {
				throw new CustomException(
					'Se importaron ' +
						successCount +
						' registros. Errores: ' +
						String.join(errors, '; ')
				);
			}

			return 'Se importaron ' + successCount + ' registros exitosamente';
		} catch (Exception e) {
			System.debug('Error en processDataImport: ' + e.getMessage());
			System.debug('Stack trace: ' + e.getStackTraceString());
			throw new AuraHandledException(e.getMessage());
		}
	}
	// Método para parsear una línea de CSV considerando comillas
	private static List<String> parseCSVLine(String line) {
		List<String> results = new List<String>();
		Boolean inQuotes = false;
		String currentValue = '';

		for (Integer i = 0; i < line.length(); i++) {
			String currentChar = line.substring(i, i + 1);

			if (currentChar == '"') {
				inQuotes = !inQuotes;
				currentValue += currentChar;
			} else if (currentChar == ',' && !inQuotes) {
				// Final de un campo
				results.add(currentValue);
				currentValue = '';
			} else {
				currentValue += currentChar;
			}
		}

		// Agregar el último valor
		if (currentValue != '') {
			results.add(currentValue);
		}

		return results;
	}
	// Método auxiliar para convertir valores
	private static Object convertValue(
		String value,
		Schema.DescribeFieldResult field
	) {
		try {
			switch on field.getType() {
				when BOOLEAN {
					return Boolean.valueOf(value.toLowerCase());
				}
				when INTEGER, LONG {
					return Integer.valueOf(value);
				}
				when DOUBLE, CURRENCY, PERCENT {
					return Decimal.valueOf(value);
				}
				when DATE {
					return Date.parse(value);
				}
				when DATETIME {
					return Datetime.parse(value);
				}
				when else {
					return value;
				}
			}
		} catch (Exception e) {
			return null;
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
			// Validar input
			if (String.isBlank(objectName)) {
				throw new AuraHandledException(
					'El nombre del objeto no puede estar vacío'
				);
			}

			List<Map<String, String>> fields = new List<Map<String, String>>();

			// Obtener el esquema del objeto
			Schema.SObjectType targetType = Schema.getGlobalDescribe()
				.get(objectName);

			if (targetType == null) {
				throw new AuraHandledException('Objeto no encontrado: ' + objectName);
			}

			// Obtener mapa de campos
			Map<String, Schema.SObjectField> fieldMap = targetType.getDescribe()
				.fields.getMap();

			// Crear una lista temporal para ordenar
			List<String> fieldLabels = new List<String>();
			Map<String, Map<String, String>> fieldsByLabel = new Map<String, Map<String, String>>();

			// Procesar cada campo
			for (String fieldName : fieldMap.keySet()) {
				Schema.DescribeFieldResult field = fieldMap.get(fieldName)
					.getDescribe();
				if (field.isAccessible()) {
					Map<String, String> fieldInfo = new Map<String, String>{
						'label' => field.getLabel(),
						'apiName' => field.getName(),
						'type' => String.valueOf(field.getType())
					};
					fieldLabels.add(field.getLabel());
					fieldsByLabel.put(field.getLabel(), fieldInfo);
				}
			}

			// Ordenar los labels
			fieldLabels.sort();

			// Reconstruir la lista ordenada
			for (String label : fieldLabels) {
				fields.add(fieldsByLabel.get(label));
			}

			return fields;
		} catch (Exception e) {
			throw new AuraHandledException(
				'Error al obtener campos: ' + e.getMessage()
			);
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
	private static SObject createRecord(
		String objectName,
		List<String> headers,
		List<String> values,
		Map<String, String> fieldMapping
	) {
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
	public class CustomException extends Exception {
	}
}
