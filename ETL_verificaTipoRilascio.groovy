// ============================================
// SCRIPT DI DETECTION TIPO DEPLOY ETL (Groovy)
// Per IBM DevOps Deploy (ex UrbanCode Deploy)
// ============================================
// Questo script analizza il contenuto della cartella ETL
// e determina quale metodologia di deploy utilizzare
//
// La variabile ${p:set-folders/environmentEtlFolder} viene sostituita
// automaticamente da IBM DevOps Deploy prima dell'esecuzione
//
// OUTPUT:
//   - outProps["TipoRilascioETL"] con valori: "ETLXML" o "APPLICATION_SH"
// ============================================

// IBM DevOps Deploy sostituisce automaticamente questa variabile
def dir2 = '${p:set-folders/environmentEtlFolder}'
def etlPath = dir2

println "=========================================="
println "RILEVAMENTO TIPO DEPLOY ETL"
println "=========================================="
println ""

// Verifica che la directory ETL esista
def etlDir = new File(etlPath)
if (!etlDir.exists() || !etlDir.isDirectory()) {
    println "ERRORE: Directory ${etlPath} non trovata o non è una directory"
    println "Path assoluto cercato: ${etlDir.absolutePath}"
    System.exit(1)
}

println "Analisi contenuto directory: ${etlDir.absolutePath}"
println ""

// Contatori per i file rilevati
int xmlCount = 0
int dtdCount = 0
int applicationShCount = 0
int ctlCount = 0

// Liste per tenere traccia dei file trovati
def xmlFiles = []
def dtdFiles = []
def applicationShFiles = []
def ctlFiles = []

// Analizza i file nella directory
etlDir.eachFile { file ->
    if (file.isFile()) {
        def fileName = file.name.trim()
       
        if (fileName.endsWith('.xml')) {
            xmlCount++
            xmlFiles << fileName
        }
       
        if (fileName.startsWith('DTD_') && fileName.endsWith('.dtd')) {
            dtdCount++
            dtdFiles << fileName
        }
       
        if (fileName.startsWith('Application_') && fileName.endsWith('.sh')) {
            applicationShCount++
            applicationShFiles << fileName
        }
       
        if (fileName.endsWith('.ctl')) {
            ctlCount++
            ctlFiles << fileName
        }
    }
}

// Report dei file rilevati
println "File rilevati:"
println "  - File XML: ${xmlCount}"
if (xmlCount > 0) {
    xmlFiles.each { println "      • ${it}" }
}
println "  - File DTD (DTD_*.dtd): ${dtdCount}"
if (dtdCount > 0) {
    dtdFiles.each { println "      • ${it}" }
}
println "  - File Application_*.sh: ${applicationShCount}"
if (applicationShCount > 0) {
    applicationShFiles.each { println "      • ${it}" }
}
println "  - File CTL: ${ctlCount}"
if (ctlCount > 0) {
    ctlFiles.each { println "      • ${it}" }
}
println ""

// Logica di decisione
String tipoRilascioETL = ""

// CASO 1: Metodologia XML + DTD
if (xmlCount > 0 && dtdCount > 0 && applicationShCount == 0) {
    tipoRilascioETL = "ETLXML"
    println "✓ RILEVATA METODOLOGIA: XML + DTD"
    println "  Tipo Rilascio: ETLXML"
    println "  Procedere con il deploy standard (pmrep import)"
    println ""
    println "  Coppie XML-DTD rilevate:"
    xmlFiles.each { xml ->
        def baseName = xml.replaceAll(/\.xml$/, '')
        def expectedDtd = "DTD_${baseName}.dtd"
       
        def dtdMatch = dtdFiles.find { it.trim() == expectedDtd }
        if (dtdMatch != null) {
            println "    ✓ ${xml} ⟷ ${expectedDtd}"
        } else {
            println "    ⚠ ${xml} (DTD corrispondente '${expectedDtd}' non trovato)"
        }
    }
   
// CASO 2: Metodologia Application_*.sh + XML
} else if (applicationShCount > 0 && xmlCount > 0) {
    tipoRilascioETL = "APPLICATION_SH"
    println "✓ RILEVATA METODOLOGIA: Application_*.sh + XML"
    println "  Tipo Rilascio: APPLICATION_SH"
    println "  Procedere con l'esecuzione degli script Application"
    if (ctlCount > 0) {
        println "  Rilevati anche ${ctlCount} file CTL che verranno gestiti"
    }
    println ""
    println "  Coppie Application-XML rilevate:"
    applicationShFiles.each { sh ->
        def baseName = sh.replaceAll(/\.sh$/, '')
        def expectedXml = "${baseName}.xml"
       
        def xmlMatch = xmlFiles.find { it.trim() == expectedXml }
        if (xmlMatch != null) {
            println "    ✓ ${sh} ⟷ ${expectedXml}"
        } else {
            println "    ⚠ ${sh} (XML corrispondente '${expectedXml}' non trovato)"
        }
    }
   
// CASO 3: Situazione ambigua o non riconosciuta
} else {
    println "✗ ERRORE: Contenuto directory non riconosciuto o ambiguo"
    println ""
    println "Situazioni rilevate:"
   
    if (xmlCount == 0) {
        println "  - PROBLEMA: Nessun file XML trovato"
    }
    if (dtdCount == 0 && applicationShCount == 0) {
        println "  - PROBLEMA: Non trovati né file DTD né file Application_*.sh"
    }
    if (dtdCount > 0 && applicationShCount > 0) {
        println "  - PROBLEMA: Trovati sia file DTD che Application_*.sh (conflitto)"
    }
   
    println ""
    println "Metodologie supportate:"
    println "  1. ETLXML: Almeno 1 file XML e almeno 1 file DTD_*.dtd"
    println "     Naming convention: nomefile.xml + DTD_nomefile.dtd"
    println "  2. APPLICATION_SH: Almeno 1 file Application_*.sh e almeno 1 file XML"
    println "     Naming convention: Application_nome.sh + Application_nome.xml"
   
    System.exit(1)
}

println ""
println "=== RISULTATO RILEVAMENTO ==="
println "TipoRilascioETL = ${tipoRilascioETL}"
println ""

// Imposta la proprietà di output per IBM DevOps Deploy
outProps.put("tipoRilascioETL", tipoRilascioETL)

println "✓ Variabile TipoRilascioETL impostata correttamente in outProps"
println ""

System.exit(0)
