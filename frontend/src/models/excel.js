function xmlText(value) {
  return String(value ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')
}

function cell(value) {
  const number = typeof value === 'number' && Number.isFinite(value)
  const content = number ? value : xmlText(value)
  return `<Cell><Data ss:Type="${number ? 'Number' : 'String'}">${content}</Data></Cell>`
}

export function exportExcel({ filename, sheet, headers, rows }) {
  const name = xmlText(String(sheet || 'Feuille').replace(/[\\/?*[\]:]/g, ' ').slice(0, 31))
  const line = (values) => `<Row>${values.map(cell).join('')}</Row>`
  const xml = `<?xml version="1.0" encoding="UTF-8"?>
<?mso-application progid="Excel.Sheet"?>
<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">
<Worksheet ss:Name="${name}"><Table>
${line(headers)}
${rows.map(line).join('')}
</Table></Worksheet>
</Workbook>`
  const blob = new Blob([xml], { type: 'application/vnd.ms-excel;charset=utf-8' })
  const link = document.createElement('a')
  link.href = URL.createObjectURL(blob)
  link.download = filename.endsWith('.xls') ? filename : `${filename}.xls`
  link.click()
  URL.revokeObjectURL(link.href)
}

export const USER_IMPORT_HEADERS = ['Nom', 'Téléphone', 'Réseau', 'Statut']

export function downloadUserImportTemplate() {
  exportExcel({
    filename: 'modele-import-utilisateurs.xls',
    sheet: 'Utilisateurs',
    headers: USER_IMPORT_HEADERS,
    rows: [
      ['Jean Mwamba', '810123456', 'orange', 'actif'],
      ['Aline Mputu', '+243815000002', 'airtel', 'actif'],
      ['Paul Kabasele', '0812345678', 'mpesa', 'suspendu'],
    ],
  })
}

function decodeXml(value) {
  return String(value ?? '')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, '&')
    .trim()
}

function parseSpreadsheetXml(text) {
  const rows = []
  const rowMatches = text.match(/<Row\b[^>]*>[\s\S]*?<\/Row>/gi) || []
  for (const rowXml of rowMatches) {
    const cells = []
    const cellRegex = /<Cell\b([^>]*)>([\s\S]*?)<\/Cell>|<Cell\b([^>]*)\/>/gi
    let match
    let nextIndex = 1
    while ((match = cellRegex.exec(rowXml))) {
      const attrs = match[1] || match[3] || ''
      const indexMatch = attrs.match(/ss:Index="(\d+)"/i)
      const index = indexMatch ? Number(indexMatch[1]) : nextIndex
      while (cells.length < index - 1) cells.push('')
      const body = match[2] || ''
      const dataMatch = body.match(/<Data\b[^>]*>([\s\S]*?)<\/Data>/i)
      cells[index - 1] = decodeXml(dataMatch ? dataMatch[1] : '')
      nextIndex = index + 1
    }
    if (cells.some((value) => String(value).trim())) rows.push(cells)
  }
  return rows
}

function parseDelimited(text) {
  const normalized = text.replace(/^\uFEFF/, '').replace(/\r\n/g, '\n').replace(/\r/g, '\n')
  const lines = normalized.split('\n').filter((line) => line.trim())
  if (!lines.length) return []
  const delimiter = lines[0].includes(';') ? ';' : ','
  return lines.map((line) => {
    const cells = []
    let current = ''
    let quoted = false
    for (let i = 0; i < line.length; i += 1) {
      const ch = line[i]
      if (ch === '"') {
        if (quoted && line[i + 1] === '"') {
          current += '"'
          i += 1
        } else {
          quoted = !quoted
        }
        continue
      }
      if (ch === delimiter && !quoted) {
        cells.push(current.trim())
        current = ''
        continue
      }
      current += ch
    }
    cells.push(current.trim())
    return cells
  })
}

function headerKey(value) {
  return String(value || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '')
}

function mapUserRows(table) {
  if (!table.length) return []
  const headers = table[0].map(headerKey)
  const find = (...names) => {
    for (const name of names) {
      const index = headers.indexOf(name)
      if (index >= 0) return index
    }
    return -1
  }
  let nameIdx = find('nom', 'name', 'fullname')
  let phoneIdx = find('telephone', 'phone', 'numero', 'msisdn')
  let networkIdx = find('reseau', 'network', 'operateur')
  let statusIdx = find('statut', 'status', 'etat')

  let dataRows = table.slice(1)
  if (nameIdx < 0 || phoneIdx < 0) {
    // Fichier sans en-tête : Nom | Téléphone | Réseau | Statut
    nameIdx = 0
    phoneIdx = 1
    networkIdx = 2
    statusIdx = 3
    dataRows = table
  }

  return dataRows
    .map((cells) => ({
      name: String(cells[nameIdx] ?? '').trim(),
      phone: String(cells[phoneIdx] ?? '').trim(),
      network: String(cells[networkIdx] ?? '').trim(),
      status: String(cells[statusIdx] ?? '').trim() || 'actif',
    }))
    .filter((row) => row.name || row.phone)
}

export async function parseUserImportFile(file) {
  const name = String(file?.name || '').toLowerCase()
  const text = await file.text()
  let table = []
  if (name.endsWith('.csv') || name.endsWith('.txt')) {
    table = parseDelimited(text)
  } else if (text.includes('<Workbook') || text.includes('<Row')) {
    table = parseSpreadsheetXml(text)
  } else if (name.endsWith('.xlsx') || name.endsWith('.xlsm')) {
    throw new Error('Enregistrez le fichier au format Excel .xls (modèle fourni) ou CSV, puis réessayez.')
  } else {
    table = text.includes(',') || text.includes(';') ? parseDelimited(text) : parseSpreadsheetXml(text)
  }
  const users = mapUserRows(table)
  if (!users.length) throw new Error('Aucune ligne utilisateur trouvée dans le fichier.')
  return users
}
