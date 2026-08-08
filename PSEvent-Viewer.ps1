Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- COLOR PALETTE (DARK MODE) ---
$bgColor      = [System.Drawing.Color]::FromArgb(32, 32, 32)      # Deep Gray
$panelColor   = [System.Drawing.Color]::FromArgb(45, 45, 48)      # Lighter Gray for containers
$controlColor = [System.Drawing.Color]::FromArgb(62, 62, 66)      # Button/Input background
$textColor    = [System.Drawing.Color]::FromArgb(241, 241, 241)  # Off-White text
$accentColor  = [System.Drawing.Color]::FromArgb(0, 122, 204)     # Windows Blue Accent
$gridLineColor = [System.Drawing.Color]::FromArgb(55, 55, 55)

# --- MAIN APPLICATION WINDOW ---
$form = New-Object System.Windows.Forms.Form
$form.Text = "Windows Event Log Deep-Dive & Exporter"
$form.Size = New-Object System.Drawing.Size(1000, 650)
$form.MinimumSize = New-Object System.Drawing.Size(800, 500)
$form.BackColor = $bgColor
$form.ForeColor = $textColor
$form.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$form.StartPosition = "CenterScreen"

# --- TOP BUTTON PANEL (Action Bar) ---
$topPanel = New-Object System.Windows.Forms.Panel
$topPanel.Height = 70
$topPanel.Dock = [System.Windows.Forms.DockStyle]::Top
$topPanel.BackColor = $panelColor
$form.Controls.Add($topPanel)

# Helper function to create uniform dark mode buttons
function Create-DarkButton ($text, $left, $width, $scriptBlock) {
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $text
    $btn.Left = $left
    $btn.Top = 15
    $btn.Width = $width
    $btn.Height = 38
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.FlatAppearance.BorderSize = 0
    $btn.BackColor = $controlColor
    $btn.ForeColor = $textColor
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btn.Add_Click($scriptBlock)
    
    # Hover effects
    $btn.Add_MouseEnter({ $this.BackColor = $accentColor })
    $btn.Add_MouseLeave({ $this.BackColor = $controlColor })
    return $btn
}

# --- DATA VIEWGRID (Responsive Results Table) ---
$dataGridView = New-Object System.Windows.Forms.DataGridView
$dataGridView.Dock = [System.Windows.Forms.DockStyle]::Fill
$dataGridView.BackgroundColor = $bgColor
$dataGridView.ForeColor = [System.Drawing.Color]::Black # Text inside rows for readability or override cell styles
$dataGridView.GridColor = $gridLineColor
$dataGridView.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
$dataGridView.AllowUserToAddRows = $false
$dataGridView.RowHeadersVisible = $false
$dataGridView.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
$dataGridView.ReadOnly = $true

# Apply specific dark mode styles to Grid Headers & Cells
$dataGridView.ColumnHeadersDefaultCellStyle.BackColor = $panelColor
$dataGridView.ColumnHeadersDefaultCellStyle.ForeColor = $textColor
$dataGridView.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$dataGridView.EnableHeadersVisualStyles = $false
$dataGridView.DefaultCellStyle.BackColor = $controlColor
$dataGridView.DefaultCellStyle.ForeColor = $textColor
$dataGridView.DefaultCellStyle.SelectionBackColor = $accentColor
$dataGridView.DefaultCellStyle.SelectionForeColor = $textColor

$form.Controls.Add($dataGridView)

# --- STATUS BAR (Bottom Panel) ---
$statusBar = New-Object System.Windows.Forms.Panel
$statusBar.Height = 35
$statusBar.Dock = [System.Windows.Forms.DockStyle]::Bottom
$statusBar.BackColor = $panelColor

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = "Ready. Select a diagnostic filter to query data."
$statusLabel.AutoSize = $true
$statusLabel.Left = 15
$statusLabel.Top = 8
$statusBar.Controls.Add($statusLabel)
$form.Controls.Add($statusBar)

# --- LOGIC & QUERIES ---

# Global variable to store active dataset for exporting
$global:currentData = @()

function Update-Grid ($data, $message) {
    $global:currentData = $data
    if ($data.Count -eq 0 -or $data -eq $null) {
        $statusLabel.Text = "Query complete: No events found matching criteria."
        $dataGridView.DataSource = $null
    } else {
        # Convert to an array list so DataGridView binds cleanly
        $arrayList = New-Object System.Collections.ArrayList
        foreach ($item in $data) { $arrayList.Add($item) | Out-Null }
        $dataGridView.DataSource = $arrayList
        $statusLabel.Text = "$message ($($data.Count) records found)."
    }
}

# 1. BSOD Errors (BugCheck 1001)
$bsodBlock = {
    $statusLabel.Text = "Querying system logs for Blue Screen events..."
    $form.Refresh()
    
    $events = Get-WinEvent -FilterHashtable @{LogName='System'; Id=1001; StartTime=(Get-Date).AddDays(-30)} -ErrorAction SilentlyContinue | 
              Select-Object TimeCreated, Id, ProviderName, Message
              
    Update-Grid $events "Loaded BSOD logs from the last 30 days"
}

# 2. Unexpected Shutdowns (Event ID 6008)
$shutdownBlock = {
    $statusLabel.Text = "Querying system logs for unexpected shutdowns..."
    $form.Refresh()
    
    $events = Get-WinEvent -FilterHashtable @{LogName='System'; Id=6008; StartTime=(Get-Date).AddDays(-30)} -ErrorAction SilentlyContinue | 
              Select-Object TimeCreated, Id, ProviderName, Message
              
    Update-Grid $events "Loaded unexpected shutdowns from the last 30 days"
}

# 3. Group Policy Failures
$gpoBlock = {
    $statusLabel.Text = "Querying Group Policy operational logs..."
    $form.Refresh()
    
    $events = Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-GroupPolicy/Operational'; Level=2; StartTime=(Get-Date).AddDays(-7)} -ErrorAction SilentlyContinue | 
              Select-Object TimeCreated, Id, LevelDisplayName, Message
              
    Update-Grid $events "Loaded Group Policy errors from the last 7 days"
}

# 4. USB Forensic History Tool
$usbBlock = {
    $statusLabel.Text = "Analyzing registry hives for USB device connections..."
    $form.Refresh()
    
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\USBSTOR"
    $usbDevices = @()
    
    if (Test-Path $regPath) {
        $devices = Get-ChildItem $regPath
        foreach ($device in $devices) {
            $instanceIds = Get-ChildItem $device.PSPath
            foreach ($instance in $instanceIds) {
                $friendlyName = (Get-ItemProperty $instance.PSPath -Name FriendlyName -ErrorAction SilentlyContinue).FriendlyName
                if (-not $friendlyName) { $friendlyName = "Unknown Storage Device" }
                
                $usbDevices += [PSCustomObject]@{
                    DeviceClass  = "USBSTOR"
                    DeviceID     = $device.PSChildName
                    SerialNumber = $instance.PSChildName
                    FriendlyName = $friendlyName
                }
            }
        }
    }
    Update-Grid $usbDevices "Loaded full hardware registry USB storage footprint"
}

# 5. Export to CSV Action
$exportBlock = {
    if ($global:currentData.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("There is no data available to export.", "Export Empty", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }
    
    $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
    $saveDialog.Filter = "CSV Files (*.csv)|*.csv"
    $saveDialog.Title = "Export Results to CSV"
    $saveDialog.FileName = "LogExport_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    
    if ($saveDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $global:currentData | Export-Csv -Path $saveDialog.FileName -NoTypeInformation
        $statusLabel.Text = "Successfully exported data to $($saveDialog.FileName)"
    }
}

# --- ADD BUTTONS TO TOP PANEL ---
$topPanel.Controls.Add((Create-DarkButton "☠️ BSOD Errors" 15 130 $bsodBlock))
$topPanel.Controls.Add((Create-DarkButton "⚠️ Bad Shutdowns" 155 140 $shutdownBlock))
$topPanel.Controls.Add((Create-DarkButton "⚙️ GPO Failures" 305 130 $gpoBlock))
$topPanel.Controls.Add((Create-DarkButton "🔌 USB History" 445 130 $usbBlock))

# Place the Export button on the far right using Anchors to keep it scalable
$btnExport = Create-DarkButton "📥 Export CSV" 845 130 $exportBlock
$btnExport.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$topPanel.Controls.Add($btnExport)

# --- RUN EXECUTION LOOP ---
$form.ShowDialog() | Out-Null
$form.Dispose()