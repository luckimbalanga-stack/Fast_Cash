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
