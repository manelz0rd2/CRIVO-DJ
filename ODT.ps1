#requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$ValidateOnly,
    [string]$ValidationSource,
    [string]$DownloadValidationFile,
    [switch]$MarketingScreenshots,
    [string]$MarketingOutput
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$AppRoot = $PSScriptRoot

if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    $hostExe = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
    Start-Process $hostExe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-File',"`"$PSCommandPath`"")
    exit
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml, System.Windows.Forms, UIAutomationClient, UIAutomationTypes
if (-not ('OdtTaskbarIdentity' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class OdtTaskbarIdentity {
    [DllImport("shell32.dll", SetLastError = true)]
    public static extern int SetCurrentProcessExplicitAppUserModelID(string appID);
    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hwnd, int command);
    public static void SetNativeDarkTitleBar(IntPtr hwnd) {
        int enabled = 1;
        if (DwmSetWindowAttribute(hwnd, 20, ref enabled, sizeof(int)) != 0)
            DwmSetWindowAttribute(hwnd, 19, ref enabled, sizeof(int));
    }
}
'@
}
[void][OdtTaskbarIdentity]::SetCurrentProcessExplicitAppUserModelID('CRIVO.DJ')
if (-not ('OdtFolderPicker' -as [type])) {
    Add-Type @'
using System;
using System.IO;
using System.Runtime.InteropServices;

public static class OdtFolderPicker {
    [Flags]
    private enum FOS : uint {
        FOS_PICKFOLDERS = 0x00000020,
        FOS_FORCEFILESYSTEM = 0x00000040,
        FOS_PATHMUSTEXIST = 0x00000800,
        FOS_DONTADDTORECENT = 0x02000000
    }
    private enum SIGDN : uint { FILESYSPATH = 0x80058000 }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct COMDLG_FILTERSPEC {
        public string pszName;
        public string pszSpec;
    }

    [ComImport, Guid("DC1C5A9C-E88A-4DDE-A5A1-60F82A20AEF7")]
    private class FileOpenDialog { }

    [ComImport, Guid("973510DB-7D7F-452B-8975-74A85828D354"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IFileDialogEvents { }

    [ComImport, Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellItem {
        void BindToHandler(IntPtr pbc, [MarshalAs(UnmanagedType.LPStruct)] Guid bhid, [MarshalAs(UnmanagedType.LPStruct)] Guid riid, out IntPtr ppv);
        void GetParent(out IShellItem ppsi);
        void GetDisplayName(SIGDN sigdnName, out IntPtr ppszName);
        void GetAttributes(uint sfgaoMask, out uint psfgaoAttribs);
        void Compare(IShellItem psi, uint hint, out int piOrder);
    }

    [ComImport, Guid("42F85136-DB7E-439C-85F1-E4075D135FC8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IFileDialog {
        [PreserveSig] int Show(IntPtr parent);
        void SetFileTypes(uint cFileTypes, [MarshalAs(UnmanagedType.LPArray)] COMDLG_FILTERSPEC[] rgFilterSpec);
        void SetFileTypeIndex(uint iFileType);
        void GetFileTypeIndex(out uint piFileType);
        void Advise(IFileDialogEvents pfde, out uint pdwCookie);
        void Unadvise(uint dwCookie);
        void SetOptions(FOS fos);
        void GetOptions(out FOS pfos);
        void SetDefaultFolder(IShellItem psi);
        void SetFolder(IShellItem psi);
        void GetFolder(out IShellItem ppsi);
        void GetCurrentSelection(out IShellItem ppsi);
        void SetFileName([MarshalAs(UnmanagedType.LPWStr)] string pszName);
        void GetFileName([MarshalAs(UnmanagedType.LPWStr)] out string pszName);
        void SetTitle([MarshalAs(UnmanagedType.LPWStr)] string pszTitle);
        void SetOkButtonLabel([MarshalAs(UnmanagedType.LPWStr)] string pszText);
        void SetFileNameLabel([MarshalAs(UnmanagedType.LPWStr)] string pszLabel);
        void GetResult(out IShellItem ppsi);
        void AddPlace(IShellItem psi, uint fdap);
        void SetDefaultExtension([MarshalAs(UnmanagedType.LPWStr)] string pszDefaultExtension);
        void Close(int hr);
        void SetClientGuid(ref Guid guid);
        void ClearClientData();
        void SetFilter(IntPtr pFilter);
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
    private static extern void SHCreateItemFromParsingName(string path, IntPtr pbc, [MarshalAs(UnmanagedType.LPStruct)] Guid riid, out IShellItem item);

    public static string Pick(IntPtr owner, string title, string initialPath) {
        IFileDialog dialog = (IFileDialog)new FileOpenDialog();
        try {
            dialog.SetOptions(FOS.FOS_PICKFOLDERS | FOS.FOS_FORCEFILESYSTEM | FOS.FOS_PATHMUSTEXIST | FOS.FOS_DONTADDTORECENT);
            dialog.SetTitle(String.IsNullOrWhiteSpace(title) ? "Selecionar pasta" : title);
            dialog.SetOkButtonLabel("Selecionar pasta");
            if (!String.IsNullOrWhiteSpace(initialPath) && Directory.Exists(initialPath)) {
                IShellItem initial = null;
                Guid iid = typeof(IShellItem).GUID;
                SHCreateItemFromParsingName(initialPath, IntPtr.Zero, iid, out initial);
                dialog.SetFolder(initial);
                if (initial != null) Marshal.ReleaseComObject(initial);
            }
            int result = dialog.Show(owner);
            if (result != 0) return null;
            IShellItem selected;
            dialog.GetResult(out selected);
            try {
                IntPtr value;
                selected.GetDisplayName(SIGDN.FILESYSPATH, out value);
                try { return Marshal.PtrToStringUni(value); }
                finally { Marshal.FreeCoTaskMem(value); }
            } finally { if (selected != null) Marshal.ReleaseComObject(selected); }
        } finally { if (dialog != null) Marshal.ReleaseComObject(dialog); }
    }
}
'@
}
foreach ($module in @('Common','Metadata','Scanner','Duplicates','History','Organizer','Enrichment','Inbox','Downloader','Rekordbox','UsbHealth','EquipmentCompatibility','UsbBackup','UsbRecovery')) {
    Import-Module (Join-Path $AppRoot "Modules\$module.psm1") -Force
}
Import-Module (Join-Path $AppRoot 'Modules\Common.psm1') -Force

$script:AppVersion = '0.9.9'
$DefaultSettingsPath = Join-Path $AppRoot 'Config\settings.json'
$SettingsPath = Join-Path (Get-AppDataRoot) 'Config\settings.json'
if(-not(Test-Path -LiteralPath $SettingsPath -PathType Leaf)){
    [IO.Directory]::CreateDirectory((Split-Path -Parent $SettingsPath))|Out-Null
    [IO.File]::Copy($DefaultSettingsPath,$SettingsPath,$false)
}
$script:Settings = Read-JsonFile -Path $SettingsPath
if(-not$script:Settings){throw "A configuração do CRIVO DJ está ausente ou inválida: $SettingsPath"}
if($script:Settings.PSObject.Properties['UnknownValues']){$script:Settings.UnknownValues.Genre='Gênero faltante'}
if($script:Settings.PSObject.Properties['GenreFallbackPriority']){$script:Settings.GenreFallbackPriority=@($script:Settings.GenreFallbackPriority|ForEach-Object{if($_ -eq '_PENDENTE'){'MissingGenre'}else{$_}})}
Write-JsonFile -Path $SettingsPath -Value $script:Settings
$script:Tracks = @()
$script:Plan = $null
$script:DuplicatePaths = @{}
$script:DestinationChosen = $false
$script:WatchSnapshot = @{}
$script:RekordboxLibrary = $null
$script:RekordboxAudit = $null
$script:RekordboxLibraryAudit = $null
$script:RekordboxUsbAudit = $null
$script:AuditMode = 'Library'
$script:AuditTracks = @()
$script:UsbHealthReport = $null
$script:UsbRecoveryPlan = $null
$script:UsbCompatibilityReport = $null
$script:UsbBackupPlan = $null
$script:DownloadQueue = New-Object Collections.ObjectModel.ObservableCollection[object]
$script:DownloadFolderTrackCount = 0
$script:DownloadStartRequested = $false
$script:CustomPlaylistName = 'CRIVO DJ — Organizado'

[xml]$xaml = Get-Content -LiteralPath (Join-Path $AppRoot 'UI\MainWindow.xaml') -Raw -Encoding UTF8
$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)
$iconPath = Join-Path $AppRoot 'Assets\CRIVO-DJ.png'
if (Test-Path -LiteralPath $iconPath) {
    try {
        $iconBitmap = New-Object Windows.Media.Imaging.BitmapImage
        $iconBitmap.BeginInit()
        $iconBitmap.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $iconBitmap.UriSource = [Uri]::new($iconPath, [UriKind]::Absolute)
        $iconBitmap.EndInit()
        $iconBitmap.Freeze()
        $window.Icon = $iconBitmap
    } catch { Write-AppLog -Message "Falha ao carregar o ícone da janela: $($_.Exception.Message)" -Level WARN }
}

$controlNames = @(
    'TitleBar','MinimizeButton','CloseButton','MainTabs',
    'SourceText','ChooseFolderButton','OrganizerOptionsScroll','ConfigPanel','ModeDate','ModeGenre','ModeDateGenre','ModeGenreBpm',
    'DestinationSame','DestinationOther',
    'FolderPatternText','CustomizeFolderCheck','TemplateVariablesButton','RenameFilesCheck','DetectDuplicatesCheck','OnlyAudioCheck','CreateReportCheck','CreateRestoreCheck',
    'DestinationText','ChooseDestinationButton','ActionCombo','ConflictCombo','DateSourceCombo','DuplicateLevelCombo','MissingPolicyCombo','WatchFolderCheck','SendRekordboxCheck','PlaylistNameFromFolderRadio','PlaylistNameCustomRadio','OrganizerPlaylistNameText','RekordboxExeText','ChooseRekordboxExeButton',
    'RulesButton','DryRunButton','FavoritesButton','DashboardButton2','ExportConfigButton','ImportConfigButton','EnrichMetadataButton','InboxButton','ImportInboxButton','DownloadStatusText','ImportRekordboxButton','ExportRekordboxButton','SystemCheckButton','ExportDiagnosticButton','EnvironmentStatusText',
    'DownloadDropPanel','DownloadUrlText','AddDownloadLinkButton','DownloadDestinationText','ChooseDownloadDestinationButton','StartDownloadButton','RemoveDownloadButton','ClearDownloadsButton','DownloadQueueGrid',
    'RekordboxXmlText','ChooseRekordboxXmlButton','AuditRekordboxButton','RekordboxSummaryText','RekordboxAuditGrid','ExportRekordboxAuditButton','EditAuditMetadataButton','ReviewAuditButton',
    'AuditLibraryModeButton','AuditUsbModeButton','AuditLibrarySourcePanel','AuditUsbSourcePanel','AuditUsbPathText','ChooseAuditUsbButton','AuditUsbButton','AuditReadOnlyText',
    'AuditCollectionCount','AuditMissingCount','AuditQualityCount','AuditDataCount','AuditDuplicateCount','AuditTotalLabel','AuditMissingLabel','AuditQualityLabel','AuditDataLabel','AuditDuplicateLabel','AuditSearchText','AuditFilterCombo',
    'ToolkitRoot','ToolkitSubTabs','ToolkitUsbPathText','ToolkitChooseUsbButton','ToolkitScanUsbButton','ToolkitProblemCount','ToolkitAttentionCount','ToolkitUnknownCount','ToolkitOverallText','ToolkitChecksGrid','ToolkitLimitText','ToolkitExportButton','ToolkitFirstAidButton',
    'EquipmentProfileCombo','ToolkitCompatibilityButton','ToolkitCompatibilityStatus','CompatibilityChecksGrid','CompatibilitySourceText','ToolkitOpenEquipmentSourceButton',
    'ToolkitBackupDestinationText','ToolkitChooseBackupDestinationButton','ToolkitBackupSummaryText','ToolkitBackupResultText','ToolkitCreateBackupButton','ToolkitRecoveryStatusText',
    'TotalCount','ReadyCount','NoGenreCount','DuplicateCount','GenreCounter1','GenreCounter2','GenreCounter3','GenreLabel1','GenreLabel2','GenreLabel3','SearchText','OrganizerListFilterCombo','PreviewGrid','PlanSummary','Progress','EditTrackMetadataButton',
    'ApplyButton','SupportCrivoButton','UndoButton','OpenHistoryButton','StatusText'
)
foreach ($name in $controlNames) { Set-Variable -Name $name -Value $window.FindName($name) -Scope Script }

function Set-AbletonWindowsTheme {
    param([Windows.DependencyObject]$Root)
    if ($Root -is [Windows.Controls.Expander]) {
        $Root.Background = [Windows.Media.Brushes]::LightGray
        $Root.Foreground = [Windows.Media.Brushes]::Black
        $Root.BorderBrush = [Windows.Media.Brushes]::Gray
    }
    for ($i=0; $i -lt [Windows.Media.VisualTreeHelper]::GetChildrenCount($Root); $i++) {
        Set-AbletonWindowsTheme -Root ([Windows.Media.VisualTreeHelper]::GetChild($Root,$i))
    }
}
Set-AbletonWindowsTheme -Root $window

function Show-CrivoDialog {
    param(
        [string]$Message,
        [string]$Title = 'CRIVO DJ',
        [string]$PrimaryText = 'OK',
        [string]$SecondaryText = '',
        [switch]$Question
    )
    $dialog=New-Object Windows.Window
    $dialog.Title="CRIVO DJ — $Title";$dialog.Width=520;$dialog.SizeToContent='Height';$dialog.MaxHeight=720
    $dialog.WindowStartupLocation='CenterOwner';$dialog.ResizeMode='NoResize';$dialog.WindowStyle='None';$dialog.ShowInTaskbar=$false
    $dialog.Background=[Windows.Media.BrushConverter]::new().ConvertFromString('#B4B0A8')
    $dialog.Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString('#171613')
    $dialog.FontFamily='Segoe UI';if($window -and $window.IsLoaded){$dialog.Owner=$window}
    if($window.Icon){$dialog.Icon=$window.Icon}
    $shell=New-Object Windows.Controls.Border;$shell.BorderBrush=[Windows.Media.BrushConverter]::new().ConvertFromString('#171613');$shell.BorderThickness='1';$shell.Padding='0'
    $layout=New-Object Windows.Controls.Grid
    foreach($height in @('Auto','Auto','Auto')){$row=New-Object Windows.Controls.RowDefinition;$row.Height=[Windows.GridLength]::Auto;$layout.RowDefinitions.Add($row)}
    $header=New-Object Windows.Controls.Border;$header.Background=[Windows.Media.BrushConverter]::new().ConvertFromString('#171613');$header.Padding='16,12'
    $headerText=New-Object Windows.Controls.TextBlock;$headerText.Text=$Title.ToUpperInvariant();$headerText.Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString('#F2F0EA');$headerText.FontWeight='Bold';$headerText.FontSize=13;$header.Child=$headerText
    [Windows.Controls.Grid]::SetRow($header,0);$layout.Children.Add($header)|Out-Null
    $content=New-Object Windows.Controls.Border;$content.Background=[Windows.Media.BrushConverter]::new().ConvertFromString('#E1DED6');$content.Padding='18,18,18,16'
    $messageText=New-Object Windows.Controls.TextBlock;$messageText.Text=$Message;$messageText.TextWrapping='Wrap';$messageText.FontSize=13;$messageText.LineHeight=20;$messageText.Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString('#171613');$content.Child=$messageText
    [Windows.Controls.Grid]::SetRow($content,1);$layout.Children.Add($content)|Out-Null
    $footer=New-Object Windows.Controls.StackPanel;$footer.Orientation='Horizontal';$footer.HorizontalAlignment='Right';$footer.Margin='12,10,12,12'
    if($SecondaryText){$secondary=New-Object Windows.Controls.Button;$secondary.Content=$SecondaryText;$secondary.MinWidth=112;$secondary.Height=36;$secondary.Margin='0,0,8,0';$secondary.Background=[Windows.Media.BrushConverter]::new().ConvertFromString('#C5C1B8');$secondary.Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString('#171613');$secondary.BorderBrush=[Windows.Media.BrushConverter]::new().ConvertFromString('#6F6A62');$secondary.Add_Click({$dialog.DialogResult=$false;$dialog.Close()});$footer.Children.Add($secondary)|Out-Null}
    $primary=New-Object Windows.Controls.Button;$primary.Content=$PrimaryText;$primary.MinWidth=112;$primary.Height=36;$primary.Background=[Windows.Media.BrushConverter]::new().ConvertFromString('#171613');$primary.Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString('#F2F0EA');$primary.BorderBrush=[Windows.Media.BrushConverter]::new().ConvertFromString('#24221F');$primary.FontWeight='Bold';$primary.Add_Click({$dialog.DialogResult=$true;$dialog.Close()});$footer.Children.Add($primary)|Out-Null
    [Windows.Controls.Grid]::SetRow($footer,2);$layout.Children.Add($footer)|Out-Null
    $shell.Child=$layout;$dialog.Content=$shell
    $result=$dialog.ShowDialog()
    return [bool]$result
}

function Show-Message {
    param([string]$Message, [string]$Title = 'CRIVO DJ', [Windows.MessageBoxImage]$Icon = [Windows.MessageBoxImage]::Information)
    [void](Show-CrivoDialog -Message $Message -Title $Title)
}

function Show-CrivoConfirm {
    param([string]$Message,[string]$Title='Confirmar',[string]$ConfirmText='CONFIRMAR',[string]$CancelText='CANCELAR')
    return (Show-CrivoDialog -Message $Message -Title $Title -PrimaryText $ConfirmText -SecondaryText $CancelText -Question)
}

function Show-SupportCrivoDialog {
    $qrPath=Join-Path $AppRoot 'Assets\Support-Pix-QR.png'
    [xml]$supportXaml=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Width="620" Height="700" WindowStartupLocation="CenterOwner" WindowStyle="None" ResizeMode="NoResize" ShowInTaskbar="False" Background="#171613" FontFamily="Segoe UI" Foreground="#171613">
  <Border BorderBrush="#171613" BorderThickness="1" Background="#D5D1C8">
    <Grid>
      <Grid.RowDefinitions><RowDefinition Height="44"/><RowDefinition Height="*"/><RowDefinition Height="62"/></Grid.RowDefinitions>
      <Grid x:Name="Header" Background="#171613">
        <TextBlock Text="APOIE O CRIVO" Foreground="#F2F0EA" FontWeight="Bold" FontSize="12" VerticalAlignment="Center" Margin="16,0,50,0"/>
        <Button x:Name="CloseButton" Content="×" Width="44" Height="43" Padding="0" HorizontalAlignment="Right" Background="#171613" Foreground="#F2F0EA" BorderThickness="0" FontSize="18"/>
      </Grid>
      <StackPanel Grid.Row="1" Margin="24,22,24,14">
        <TextBlock Text="AJUDE A MELHORAR O CRIVO DJ" FontSize="18" FontWeight="Bold"/>
        <TextBlock Text="Envie feedbacks, erros encontrados e sugestões de ajustes." Foreground="#57534C" FontSize="11" Margin="0,5,0,16"/>
        <Border Background="#E5E2DA" BorderBrush="#969188" BorderThickness="1" Padding="14,11">
          <StackPanel><TextBlock Text="E-MAIL" FontSize="9" FontWeight="Bold"/><TextBlock Text="emanuel.pereira.fraga@gmail.com" FontSize="14" FontWeight="SemiBold" Margin="0,4,0,0"/></StackPanel>
        </Border>
        <TextBlock Text="PIX PARA APOIO:" FontSize="11" FontWeight="Bold" HorizontalAlignment="Center" Margin="0,20,0,10"/>
        <Border Width="316" Height="316" HorizontalAlignment="Center" Background="#FFFFFF" BorderBrush="#171613" BorderThickness="3" ClipToBounds="True">
          <Canvas Width="316" Height="316" ClipToBounds="True"><Image x:Name="QrImage" Width="410" Height="889" Canvas.Left="-55" Canvas.Top="-206" Stretch="Fill"/></Canvas>
        </Border>
        <TextBlock Text="Aponte a câmera do celular para o QR Code." Foreground="#57534C" FontSize="10" HorizontalAlignment="Center" Margin="0,10,0,0"/>
      </StackPanel>
      <Grid Grid.Row="2" Margin="24,10,24,16">
        <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="10"/><ColumnDefinition/></Grid.ColumnDefinitions>
        <Button x:Name="EmailButton" Content="ENVIAR E-MAIL" Height="36" Background="#C5C1B8" Foreground="#171613" BorderBrush="#77726A" FontWeight="Bold"/>
        <Button x:Name="DoneButton" Grid.Column="2" Content="FECHAR" Height="36" Background="#171613" Foreground="#F2F0EA" BorderBrush="#171613" FontWeight="Bold"/>
      </Grid>
    </Grid>
  </Border>
</Window>
'@
    $reader=New-Object System.Xml.XmlNodeReader $supportXaml
    $dialog=[Windows.Markup.XamlReader]::Load($reader);if($window -and $window.IsLoaded){$dialog.Owner=$window};if($window.Icon){$dialog.Icon=$window.Icon}
    if(Test-Path -LiteralPath $qrPath){$bitmap=New-Object Windows.Media.Imaging.BitmapImage;$bitmap.BeginInit();$bitmap.CacheOption=[Windows.Media.Imaging.BitmapCacheOption]::OnLoad;$bitmap.UriSource=[Uri]::new($qrPath,[UriKind]::Absolute);$bitmap.EndInit();$bitmap.Freeze();$dialog.FindName('QrImage').Source=$bitmap}
    $dialog.FindName('Header').Add_MouseLeftButtonDown({if($_.ClickCount -eq 1){try{$dialog.DragMove()}catch{}}})
    $dialog.FindName('CloseButton').Add_Click({$dialog.Close()})
    $dialog.FindName('DoneButton').Add_Click({$dialog.Close()})
    $dialog.FindName('EmailButton').Add_Click({try{Start-Process 'mailto:emanuel.pereira.fraga@gmail.com?subject=Feedback%20CRIVO%20DJ'}catch{Show-Message 'E-mail: emanuel.pereira.fraga@gmail.com' 'Apoie o CRIVO'}})
    [void]$dialog.ShowDialog()
}

function Set-CrivoFormStyle {
    param([Parameter(Mandatory)][Windows.Forms.Form]$Form,[string]$Title='CRIVO DJ')
    $existing=@($Form.Controls);$Form.Controls.Clear();$Form.FormBorderStyle='None';$Form.Padding=New-Object Windows.Forms.Padding(1);$Form.BackColor=[Drawing.Color]::FromArgb(23,22,19)
    $body=New-Object Windows.Forms.Panel;$body.Dock='Fill';$body.BackColor=[Drawing.Color]::FromArgb(202,198,189);foreach($control in $existing){$body.Controls.Add($control)}
    $header=New-Object Windows.Forms.Panel;$header.Dock='Top';$header.Height=38;$header.BackColor=[Drawing.Color]::FromArgb(23,22,19)
    $label=New-Object Windows.Forms.Label;$label.Dock='Fill';$label.Padding=New-Object Windows.Forms.Padding(13,10,0,0);$label.Text=$Title.ToUpperInvariant();$label.Font=New-Object Drawing.Font('Arial',9,[Drawing.FontStyle]::Bold);$label.ForeColor=[Drawing.Color]::FromArgb(242,240,234);$header.Controls.Add($label)
    $close=New-Object Windows.Forms.Button;$close.Dock='Right';$close.Width=42;$close.FlatStyle='Flat';$close.FlatAppearance.BorderSize=0;$close.Text='×';$close.Font=New-Object Drawing.Font('Arial',13,[Drawing.FontStyle]::Bold);$close.BackColor=[Drawing.Color]::FromArgb(23,22,19);$close.ForeColor=[Drawing.Color]::FromArgb(242,240,234);$close.Tag=$Form;$close.Add_Click({param($sender)$target=[Windows.Forms.Form]$sender.Tag;$target.DialogResult=[Windows.Forms.DialogResult]::Cancel;$target.Close()});$header.Controls.Add($close);$close.BringToFront()
    $Form.Controls.Add($body);$Form.Controls.Add($header);$header.BringToFront()
}

function Pump-Ui { [Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action]{}, [Windows.Threading.DispatcherPriority]::Background) }

function Set-Status {
    param([string]$Text, [int]$Percent = -1)
    $StatusText.Text = $Text
    if ($Percent -ge 0) { $Progress.Value = $Percent }
    Pump-Ui
}

function New-UiProgressAction {
    param([Parameter(Mandatory)][scriptblock]$Message,[Parameter(Mandatory)][scriptblock]$Percent)
    $statusControl=$StatusText;$progressControl=$Progress;$dispatcher=[Windows.Threading.Dispatcher]::CurrentDispatcher
    return {
        param($current,$total,$name,$phase)
        $statusControl.Text=[string](& $Message $current $total $name $phase)
        $progressControl.Value=[int](& $Percent $current $total $name $phase)
        $dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::Background)
    }.GetNewClosure()
}

function Get-SelectedTag {
    param($Combo)
    if ($Combo.SelectedItem -and $Combo.SelectedItem.Tag) { return [string]$Combo.SelectedItem.Tag }
    return ''
}

function Select-Folder {
    param([string]$Description, [string]$InitialPath)
    $owner = [Windows.Interop.WindowInteropHelper]::new($window).Handle
    return [OdtFolderPicker]::Pick($owner, $Description, $InitialPath)
}

function Save-Settings { Write-JsonFile -Path $SettingsPath -Value $script:Settings }

function Select-ComboTag {
    param($Combo, [string]$Tag)
    foreach ($item in @($Combo.Items)) { if ([string]$item.Tag -eq $Tag) { $Combo.SelectedItem = $item; return } }
}

function Get-DefaultTemplate {
    if ($ModeDate.IsChecked) { return '{AAAA} - {MES_NUM} - {MES}' }
    if ($ModeGenre.IsChecked) { return '{GENERO}' }
    if ($ModeGenreBpm.IsChecked) { return '{GENERO} - {BPM_RANGE}' }
    return '{AAAA} - {MES_NUM} - {MES} - {GENERO}'
}

function Get-DefaultOrganizerPlaylistName {
    param([string]$Path)
    $folderName='Organizado'
    if($Path){
        try{$folderName=Split-Path ([IO.Path]::GetFullPath($Path).TrimEnd('\')) -Leaf}catch{}
    }
    if([string]::IsNullOrWhiteSpace($folderName)){$folderName='Organizado'}
    return 'CRIVO DJ — '+(ConvertTo-SafePathPart $folderName 'Organizado')
}

function Get-AutomaticOrganizerPlaylistName {
    if($script:Plan -and $script:Plan.Items){
        $folderNames=@($script:Plan.Items|Where-Object{$_.Status -eq 'Ready' -and $_.Destination}|ForEach-Object{try{Split-Path (Split-Path ([string]$_.Destination) -Parent) -Leaf}catch{}}|Where-Object{$_}|Select-Object -Unique)
        if($folderNames.Count -eq 1){return [string]$folderNames[0]}
    }
    if($script:DestinationChosen -and (Test-Path -LiteralPath (Split-Path $DestinationText.Text -Parent) -PathType Container)){
        try{$name=Split-Path ([IO.Path]::GetFullPath($DestinationText.Text).TrimEnd('\')) -Leaf;if($name){return $name}}catch{}
    }
    return Get-DefaultOrganizerPlaylistName -Path $SourceText.Text
}

function Sync-OrganizerPlaylistName {
    $enabled=[bool]$SendRekordboxCheck.IsChecked
    $PlaylistNameFromFolderRadio.IsEnabled=$enabled;$PlaylistNameCustomRadio.IsEnabled=$enabled
    if(-not$enabled){$OrganizerPlaylistNameText.IsEnabled=$false;return}
    if($PlaylistNameCustomRadio.IsChecked){
        $OrganizerPlaylistNameText.IsEnabled=$true;$OrganizerPlaylistNameText.IsReadOnly=$false
        if([string]::IsNullOrWhiteSpace($OrganizerPlaylistNameText.Text) -or $OrganizerPlaylistNameText.Text -eq (Get-AutomaticOrganizerPlaylistName)){$OrganizerPlaylistNameText.Text=$script:CustomPlaylistName}
    }else{
        $OrganizerPlaylistNameText.Text=Get-AutomaticOrganizerPlaylistName
        $OrganizerPlaylistNameText.IsReadOnly=$true;$OrganizerPlaylistNameText.IsEnabled=$true
    }
}

function Get-CurrentTemplate { return $FolderPatternText.Text.Trim() }

function Sync-FolderPattern {
    $FolderPatternText.IsReadOnly = -not [bool]$CustomizeFolderCheck.IsChecked
    $TemplateVariablesButton.IsEnabled = [bool]$CustomizeFolderCheck.IsChecked
    if (-not $CustomizeFolderCheck.IsChecked) { $FolderPatternText.Text = Get-DefaultTemplate }
}

function Show-TemplateVariablesDialog {
    $variables=@(
        [pscustomobject]@{Token='{AAAA}';Description='Ano com quatro dígitos'},[pscustomobject]@{Token='{AA}';Description='Ano com dois dígitos'},
        [pscustomobject]@{Token='{MES}';Description='Nome do mês'},[pscustomobject]@{Token='{MES_NUM}';Description='Número do mês'},[pscustomobject]@{Token='{DIA}';Description='Dia'},
        [pscustomobject]@{Token='{GENERO}';Description='Gênero'},[pscustomobject]@{Token='{ARTISTA}';Description='Artista'},[pscustomobject]@{Token='{ALBUM}';Description='Álbum'},[pscustomobject]@{Token='{ANO}';Description='Ano informado na track'},
        [pscustomobject]@{Token='{BPM}';Description='BPM, quando já estiver disponível'},[pscustomobject]@{Token='{BPM_RANGE}';Description='Faixa de BPM, quando disponível'},[pscustomobject]@{Token='{KEY}';Description='Tonalidade, quando disponível'},
        [pscustomobject]@{Token='{EXTENSAO}';Description='Extensão do arquivo'},[pscustomobject]@{Token='{FORMATO}';Description='Formato do áudio'},[pscustomobject]@{Token='{PASTA_ORIGEM}';Description='Pasta de origem'},
        [pscustomobject]@{Token='{PASTA_PAI}';Description='Pasta pai'},[pscustomobject]@{Token='{PASTA_RAIZ}';Description='Pasta raiz'},[pscustomobject]@{Token='{NOME_ARQUIVO}';Description='Nome atual do arquivo'},
        [pscustomobject]@{Token='{TITULO}';Description='Título da track'},[pscustomobject]@{Token='{BITRATE}';Description='Bitrate'},[pscustomobject]@{Token='{SAMPLE_RATE}';Description='Sample rate'}
    )
    $dialog=New-Object Windows.Window;$dialog.Title='CRIVO DJ — Opções do nome';$dialog.Width=600;$dialog.Height=560;$dialog.WindowStartupLocation='CenterOwner';if($window -and $window.IsLoaded){$dialog.Owner=$window};$dialog.ResizeMode='NoResize';$dialog.WindowStyle='None';$dialog.ShowInTaskbar=$false;$dialog.Background=[Windows.Media.BrushConverter]::new().ConvertFromString('#B4B0A8');$dialog.Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString('#171613');if($window.Icon){$dialog.Icon=$window.Icon}
    $layout=New-Object Windows.Controls.Grid;foreach($height in @('Auto','Auto','*','Auto')){$row=New-Object Windows.Controls.RowDefinition;$row.Height=$height;$layout.RowDefinitions.Add($row)}
    $header=New-Object Windows.Controls.Border;$header.Background=[Windows.Media.BrushConverter]::new().ConvertFromString('#171613');$header.Padding='16,12';$title=New-Object Windows.Controls.TextBlock;$title.Text='OPÇÕES PARA MONTAR O NOME';$title.Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString('#F2F0EA');$title.FontWeight='Bold';$header.Child=$title;$header.Add_MouseLeftButtonDown({try{$dialog.DragMove()}catch{}});$layout.Children.Add($header)|Out-Null
    $intro=New-Object Windows.Controls.TextBlock;$intro.Text='Combine texto livre com informações da track ou da pasta. Escolha uma opção abaixo para inseri-la na posição atual do nome.';$intro.TextWrapping='Wrap';$intro.Margin='16,14,16,12';[Windows.Controls.Grid]::SetRow($intro,1);$layout.Children.Add($intro)|Out-Null
    $list=New-Object Windows.Controls.ListBox;$list.Margin='16,0,16,12';$list.Background=[Windows.Media.BrushConverter]::new().ConvertFromString('#E1DED6');$list.BorderBrush=[Windows.Media.BrushConverter]::new().ConvertFromString('#777269');$list.DisplayMemberPath='Display';foreach($item in $variables){$item|Add-Member NoteProperty Display ("{0}    {1}" -f $item.Token,$item.Description);[void]$list.Items.Add($item)};[Windows.Controls.Grid]::SetRow($list,2);$layout.Children.Add($list)|Out-Null
    $buttons=New-Object Windows.Controls.StackPanel;$buttons.Orientation='Horizontal';$buttons.HorizontalAlignment='Right';$buttons.Margin='16,0,16,14'
    $close=New-Object Windows.Controls.Button;$close.Content='FECHAR';$close.Width=105;$close.Height=34;$close.Margin='0,0,8,0';$close.Add_Click({$dialog.Close()});$buttons.Children.Add($close)|Out-Null
    $insert=New-Object Windows.Controls.Button;$insert.Content='INSERIR';$insert.Width=115;$insert.Height=34;$insert.Background=[Windows.Media.BrushConverter]::new().ConvertFromString('#171613');$insert.Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString('#F2F0EA');$insert.FontWeight='Bold';$insert.Add_Click({if($list.SelectedItem){$CustomizeFolderCheck.IsChecked=$true;Sync-FolderPattern;$token=[string]$list.SelectedItem.Token;$position=[Math]::Min($FolderPatternText.SelectionStart,$FolderPatternText.Text.Length);$FolderPatternText.Text=$FolderPatternText.Text.Insert($position,$token);$FolderPatternText.SelectionStart=$position+$token.Length;$FolderPatternText.Focus();$dialog.Close()}});$buttons.Children.Add($insert)|Out-Null
    [Windows.Controls.Grid]::SetRow($buttons,3);$layout.Children.Add($buttons)|Out-Null;$dialog.Content=$layout;[void]$dialog.ShowDialog()
}

function Get-TemplateCriteriaError {
    param([string]$Template)
    if($CustomizeFolderCheck.IsChecked){return $null}
    $hasDate = $Template -match '\{(AAAA|AA|MES|MES_NUM|DIA)\}'
    $hasGenre = $Template -match '\{GENERO\}'
    $hasBpm = $Template -match '\{(BPM|BPM_RANGE)\}'
    if ($ModeDate.IsChecked -and -not $hasDate) { return 'O modelo personalizado precisa manter pelo menos um campo de data.' }
    if ($ModeGenre.IsChecked -and -not $hasGenre) { return 'O modelo personalizado precisa manter o campo {GENERO}.' }
    if ($ModeDateGenre.IsChecked -and (-not $hasDate -or -not $hasGenre)) { return 'O modelo personalizado precisa manter um campo de data e o campo {GENERO}.' }
    if ($ModeGenreBpm.IsChecked -and (-not $hasGenre -or -not $hasBpm)) { return 'O modelo personalizado precisa manter {GENERO} e {BPM} ou {BPM_RANGE}.' }
    return $null
}

function Invalidate-Plan {
    $script:Plan = $null
    $ApplyButton.IsEnabled = $false
    if ($script:Tracks.Count -and $script:DestinationChosen) { Update-OrganizationPlan }
    elseif ($ConfigPanel.IsEnabled -and $script:Tracks.Count) { $PlanSummary.Text = 'Última etapa: escolha onde salvar as pastas organizadas.' }
}

function Refresh-UndoState {
    $latest = @(Get-OperationHistory | Where-Object { -not $_.UndoneAt } | Select-Object -First 1)
    $UndoButton.IsEnabled = ($latest.Count -gt 0)
}

function Refresh-PreviewFilter {
    if (-not $PreviewGrid.ItemsSource) { return }
    $view = [Windows.Data.CollectionViewSource]::GetDefaultView($PreviewGrid.ItemsSource)
    $search = $SearchText.Text.Trim().ToLowerInvariant()
    $onlyMissingMetadata = (Get-SelectedTag $OrganizerListFilterCombo) -eq 'Missing'
    $predicate = [Predicate[object]]{
        param($item)
        $trackText = "$($item.Name) $($item.OutputName) $($item.Title)".ToLowerInvariant()
        $matchesSearch = -not $search -or $trackText.Contains($search)
        $hasMissingMetadata = $item.MissingTitle -or -not $item.Artist -or -not $item.Album -or $item.MissingGenre -or -not $item.Genre -or -not $item.Year
        return $matchesSearch -and (-not $onlyMissingMetadata -or $hasMissingMetadata)
    }.GetNewClosure()
    $view.Filter = $predicate; $view.Refresh()
}

function Update-TrackMetadataStatus {
    param([Parameter(Mandatory)]$Track,[string]$Override='')
    if($Override){$value=$Override}else{
        $labels=New-Object Collections.Generic.List[string]
        if($Track.MissingTitle -or -not$Track.Title){$labels.Add('Título faltante')}
        if(-not$Track.Artist){$labels.Add('Artista faltante')}
        if(-not$Track.Album){$labels.Add('Álbum faltante')}
        if($Track.MissingGenre -or -not$Track.Genre){$labels.Add('Gênero faltante')}
        if(-not$Track.Year){$labels.Add('Ano faltante')}
        $value=if($labels.Count){$labels -join ' • '}else{'Dados completos'}
    }
    if($Track.PSObject.Properties['MetadataStatus']){$Track.MetadataStatus=$value}else{$Track|Add-Member NoteProperty MetadataStatus $value}
}

function Update-Dashboard {
    $health = Get-LibraryHealth -Tracks @($script:Tracks)
    $TotalCount.Text = [string]$health.Total
    $missing=@($script:Tracks|Where-Object{$_.MissingTitle -or -not$_.Artist -or -not$_.Album -or $_.MissingGenre -or -not$_.Genre -or -not$_.Year}).Count
    $GenreLabel1.Text='TRACKS COM DADOS FALTANTES';$ReadyCount.Text=[string]$missing;$GenreCounter1.Visibility='Visible'
    $GenreCounter2.Visibility='Collapsed';$GenreCounter3.Visibility='Collapsed'
}

function Update-Duplicates {
    $script:DuplicatePaths = @{}
    if ($DetectDuplicatesCheck.IsChecked -and $script:Tracks.Count) {
        $level = Get-SelectedTag $DuplicateLevelCombo
        if ($level -eq 'Hash' -and @($script:Tracks | Where-Object { -not $_.Hash }).Count) { return }
        foreach ($track in @(Find-AudioDuplicates -Tracks $script:Tracks -Level $level)) {
            $script:DuplicatePaths[$track.FullName] = $true
        }
    }
    Update-Dashboard
    Refresh-PreviewFilter
}

function Scan-SelectedFolder {
    param([switch]$IncludeHash)
    $source = $SourceText.Text.Trim()
    if (-not (Test-Path -LiteralPath $source -PathType Container)) { return $false }
    try {
        $ChooseFolderButton.IsEnabled = $false; $ApplyButton.IsEnabled = $false; $EditTrackMetadataButton.IsEnabled=$false
        $progressAction=New-UiProgressAction -Message {param($current,$total,$name) "Lendo $name ($current de $total)"} -Percent {param($current,$total) if($total){[int](($current/$total)*100)}else{0}}
        $script:Tracks = @(Get-AudioFiles -Source $source -Settings $script:Settings -IncludeHash:$IncludeHash -OnlyAudio:([bool]$OnlyAudioCheck.IsChecked) -OnProgress $progressAction)
        $PreviewGrid.ItemsSource = $script:Tracks
        Update-Duplicates
        if ($script:Tracks.Count) {
            $PlanSummary.Text = "$($script:Tracks.Count) track(s) analisada(s). Configure a organização e escolha o destino."
            Set-Status 'Pasta analisada — aguardando destino da organização' 100
        } else {
            $PlanSummary.Text = 'Nenhum arquivo de áudio compatível foi encontrado nesta pasta.'
            Set-Status 'Pasta analisada — nenhum arquivo de áudio encontrado' 0
        }
        return $true
    } catch {
        Write-AppLog -Message $_.Exception.ToString() -Level ERROR
        Show-Message $_.Exception.Message 'Não foi possível analisar a pasta' Error
        Set-Status 'Falha ao analisar a pasta' 0
        return $false
    } finally {
        $ChooseFolderButton.IsEnabled = $true
    }
}

function Get-WatchCandidates {
    param([Parameter(Mandatory)][string]$Source)
    $sourceRoot=[IO.Path]::GetFullPath($Source).TrimEnd('\');$audio=@($script:Settings.AudioExtensions|ForEach-Object{$_.ToLowerInvariant()});$ignoredExt=@($script:Settings.ExcludedExtensions|ForEach-Object{$_.ToLowerInvariant()});$ignoredFolders=@($script:Settings.ExcludedFolders)
    return @(Get-ChildItem -LiteralPath $Source -File -Recurse -ErrorAction SilentlyContinue|Where-Object{$file=$_;$relative=$file.FullName.Substring($sourceRoot.Length).TrimStart([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar);$parts=@($relative -split '[\\/]+'|Where-Object{$_});$ignoredFolder=@($parts|Where-Object{$_ -in $ignoredFolders}).Count -gt 0;$extension=$file.Extension.ToLowerInvariant();-not$ignoredFolder -and $ignoredExt -notcontains $extension -and ((-not$OnlyAudioCheck.IsChecked) -or $audio -contains $extension)})
}

function Update-OrganizationPlan {
    $source = $SourceText.Text.Trim(); $destination = $DestinationText.Text.Trim(); $template = Get-CurrentTemplate
    if (-not (Test-Path -LiteralPath $source -PathType Container) -or -not $script:DestinationChosen) { return $false }
    if ([string]::IsNullOrWhiteSpace($template)) { $PlanSummary.Text='Informe como ficará a pasta.'; return $false }
    $criteriaError = Get-TemplateCriteriaError -Template $template
    if ($criteriaError) { $PlanSummary.Text=$criteriaError; Set-Status 'Modelo de pasta incompleto' 0; return $false }
    try {
        $ApplyButton.IsEnabled = $false
        $needHash = (Get-SelectedTag $ConflictCombo) -eq 'CompareHash' -or (Get-SelectedTag $DuplicateLevelCombo) -eq 'Hash'
        if (-not $script:Tracks.Count -or ($needHash -and @($script:Tracks | Where-Object { -not $_.Hash }).Count)) {
            if (-not (Scan-SelectedFolder -IncludeHash:$needHash)) { return $false }
        }
        if (-not $script:Tracks.Count) { $PreviewGrid.ItemsSource=@(); Update-Dashboard; $PlanSummary.Text='Nenhuma track de áudio encontrada.'; Set-Status 'Nenhuma track encontrada' 0; return $false }

        Update-Duplicates
        Set-Status 'Calculando destinos automaticamente…' 65
        $script:Plan = New-OrganizationPlan -Tracks $script:Tracks -Source $source -Destination $destination -Template $template -TreeMode 'FlattenSource' -Action (Get-SelectedTag $ActionCombo) -Conflict (Get-SelectedTag $ConflictCombo) -DateSource (Get-SelectedTag $DateSourceCombo) -RenameFiles:$RenameFilesCheck.IsChecked -MissingMetadataPolicy (Get-SelectedTag $MissingPolicyCombo) -CreateReport:$CreateReportCheck.IsChecked -CreateRestore:$CreateRestoreCheck.IsChecked -Settings $script:Settings
        $PreviewGrid.ItemsSource = $script:Tracks
        Update-Dashboard; Refresh-PreviewFilter;Sync-OrganizerPlaylistName
        $ready = @($script:Plan.Items | Where-Object Status -eq 'Ready').Count; $blocked = @($script:Plan.Items | Where-Object Status -in @('Error','Conflict')).Count; $skipped = @($script:Plan.Items | Where-Object Status -eq 'Skip').Count
        $PlanSummary.Text = "$ready serão organizados em $destination • $skipped ignorados • $blocked conflitos/erros"
        $ApplyButton.IsEnabled = ($ready -gt 0 -and $blocked -eq 0)
        Set-Status 'Destinos calculados — revise a tabela ou organize agora' 100
        return $true
    } catch {
        Write-AppLog -Message $_.Exception.ToString() -Level ERROR
        $PlanSummary.Text=$_.Exception.Message
        Set-Status 'Falha ao calcular os destinos' 0
        return $false
    }
}

function Invoke-CurrentPlan {
    if (-not $script:Plan) { return }
    $destinationRoot=[IO.Path]::GetFullPath($script:Plan.Destination).TrimEnd('\')+'\';$reserved=@{}
    foreach ($item in @($script:Plan.Items | Where-Object Status -eq 'Ready')) {
        try{$edited=[IO.Path]::GetFullPath([string]$item.Track.Destination)}catch{Show-Message "O destino informado não é válido para '$($item.Track.Name)'." 'Destino inválido' Error;return}
        if(-not $edited.StartsWith($destinationRoot,[StringComparison]::OrdinalIgnoreCase)){Show-Message "O destino editado precisa permanecer dentro da pasta escolhida:`n$edited" 'Destino inválido' Error;return}
        if($edited.Length -ge 248){Show-Message "O destino editado é longo demais:`n$edited" 'Destino inválido' Error;return}
        if($reserved.ContainsKey($edited.ToLowerInvariant())){Show-Message "Duas faixas apontam para o mesmo destino:`n$edited" 'Conflito no plano' Error;return}
        $reserved[$edited.ToLowerInvariant()]=$true;$item.Destination=$edited
    }
    $verb = if ($script:Plan.Action -eq 'Move') { 'mover' } else { 'copiar' }
    $rekordboxWarning=if($SendRekordboxCheck.IsChecked){"`n`nO CRIVO DJ também gravará a playlist diretamente no banco do Rekordbox. O Rekordbox e o rekordboxAgent precisam estar fechados; um backup será criado antes da escrita."}else{''}
    if (-not(Show-CrivoConfirm -Message "Confirmar e $verb $(@($script:Plan.Items | Where-Object Status -eq 'Ready').Count) track(s)?$rekordboxWarning" -Title 'Confirmar organização' -ConfirmText 'ORGANIZAR')) { return }
    try {
        $ChooseFolderButton.IsEnabled=$false; $ApplyButton.IsEnabled=$false
        $progressAction=New-UiProgressAction -Message {param($current,$total,$name) "Organizando $name ($current de $total)"} -Percent {param($current,$total) [int](($current/[Math]::Max(1,$total))*100)}
        $result = Invoke-OrganizationPlan -Plan $script:Plan -OnProgress $progressAction
        Refresh-UndoState
        $extra = ''; if ($result.ReportPath) { $extra += "`nRelatório: $($result.ReportPath)" }; if ($result.HistoryPath) { $extra += "`nPonto de restauração criado." }
        if($SendRekordboxCheck.IsChecked){try{$rb=Export-OrganizedPlanToRekordbox -Plan $script:Plan -Operation $result.Operation;if($rb){$needsAnalysis=if($rb.Import.PSObject.Properties['tracksNeedingAnalysis']){[int]$rb.Import.tracksNeedingAnalysis}else{0};$analysisText=if($needsAnalysis -gt 0){"`n$needsAnalysis track(s) aguardam a análise oficial do Rekordbox (waveform e beatgrid)."}else{"`nAs tracks já possuem análise do Rekordbox."};$extra+="`nPlaylist Rekordbox '$($rb.PlaylistName)' gravada diretamente e verificada ($($rb.Count) tracks).$analysisText`nBackup: $($rb.Import.BackupPath)"}}catch{Write-AppLog -Message $_.Exception.ToString() -Level ERROR;$extra+="`nFalha na gravação direta do Rekordbox: $($_.Exception.Message)"}}
        $completedCount=$result.Success;$skippedCount=if($result.PSObject.Properties['Skipped']){[int]$result.Skipped}else{0}
        [void](Scan-SelectedFolder);$script:Plan=$null;$ApplyButton.IsEnabled=$false
        if([int]$result.Errors -gt 0){
            $PlanSummary.Text="Organização concluída com atenção • $completedCount track(s) processada(s) • $skippedCount ignorada(s) • $($result.Errors) erro(s)"
            Set-Status 'Organização terminou com erros. Revise o resultado.' 100
            Show-Message "A organização terminou, mas nem tudo foi concluído.`n`nProcessadas: $completedCount`nIgnoradas: $skippedCount`nErros: $($result.Errors)$extra" 'Organização concluída com atenção' Warning
        }elseif($completedCount -gt 0){
            $PlanSummary.Text="Organização concluída • $completedCount track(s) processada(s) • $skippedCount ignorada(s) • nenhum erro"
            Set-Status 'Organização concluída. Lista atualizada.' 100
            Show-Message "Organização concluída.`n`nProcessadas: $completedCount`nIgnoradas: $skippedCount`nErros: 0$extra" 'Tudo pronto'
        }else{
            $PlanSummary.Text="Nenhuma track foi processada • $skippedCount ignorada(s)"
            Set-Status 'Nenhuma track foi organizada.' 0
            Show-Message "Nenhuma track foi organizada.`n`nIgnoradas: $skippedCount" 'Nada foi alterado' Warning
        }
        Update-ContextInformation
    } catch {
        Write-AppLog -Message $_.Exception.ToString() -Level ERROR
        Show-Message $_.Exception.Message 'Erro durante a organização' Error
    } finally { $ChooseFolderButton.IsEnabled=$true }
}

function Show-LibraryDashboard {
    $health = Get-LibraryHealth -Tracks @($script:Tracks)
    $last = @(Get-OperationHistory | Select-Object -First 1)
    $lastText = if ($last.Count) { $n=if($last[0].PSObject.Properties['Counts']){$last[0].Counts.Total}else{@($last[0].Items).Count}; "$($last[0].Date) — $n track(s)" } else { 'nenhuma execução' }
    $pending = if($script:Plan){@($script:Plan.Items | Where-Object Status -in @('Skip','Error','Conflict')).Count}else{0}
    Show-Message ("ANÁLISE PRÉVIA`n`nTracks: {0}`nIgnoradas/conflitos: {1}`nDuplicatas: {2}`nSem título: {3}`nSem artista: {4}`nSem álbum: {5}`nSem ano: {6}`nSem gênero: {7}`nSem BPM: {8}`nSem tonalidade: {9}`nCorrompidas/inacessíveis: {10}`nQualidade suspeita: {11}`n`nÚltima organização: {12}" -f $health.Total,$pending,$script:DuplicatePaths.Count,$health.MissingTitle,$health.MissingArtist,$health.MissingAlbum,$health.MissingYear,$health.MissingGenre,$health.MissingBpm,$health.MissingKey,$health.Corrupt,$health.QualityIssues,$lastText) 'Análise prévia'
}

function Show-MetadataReview {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Matches)
    if(-not$Matches.Count){Show-Message 'Nenhum dado correspondente foi encontrado nas fontes online.' 'Buscar dados ausentes';return}
    $form=New-Object Windows.Forms.Form;$form.Text='CRIVO DJ — Revisar dados encontrados online';$form.Width=1120;$form.Height=650;$form.StartPosition='CenterParent';$form.Font=New-Object Drawing.Font('Arial',9);$form.BackColor=[Drawing.Color]::FromArgb(195,195,195);$form.ForeColor=[Drawing.Color]::FromArgb(20,20,20)
    $grid=New-Object Windows.Forms.DataGridView;$grid.Dock='Fill';$grid.AllowUserToAddRows=$false;$grid.AllowUserToDeleteRows=$false;$grid.AutoSizeRowsMode='AllCells';$grid.BackgroundColor=[Drawing.Color]::FromArgb(200,200,200);$grid.ForeColor=[Drawing.Color]::FromArgb(20,20,20);$grid.GridColor=[Drawing.Color]::FromArgb(130,130,130);$grid.RowHeadersVisible=$false;$grid.SelectionMode='FullRowSelect';$grid.DefaultCellStyle.BackColor=[Drawing.Color]::FromArgb(218,218,218);$grid.DefaultCellStyle.ForeColor=[Drawing.Color]::FromArgb(20,20,20);$grid.DefaultCellStyle.SelectionBackColor=[Drawing.Color]::FromArgb(229,139,42);$grid.DefaultCellStyle.SelectionForeColor=[Drawing.Color]::Black;$grid.ColumnHeadersDefaultCellStyle.BackColor=[Drawing.Color]::FromArgb(172,172,172);$grid.ColumnHeadersDefaultCellStyle.ForeColor=[Drawing.Color]::Black;$grid.EnableHeadersVisualStyles=$false
    $check=New-Object Windows.Forms.DataGridViewCheckBoxColumn;$check.HeaderText='USAR';$check.Width=55;[void]$grid.Columns.Add($check)
    foreach($spec in @(@('ARQUIVO',180),@('DADOS ATUAIS',240),@('ENCONTRADO ONLINE',300),@('CONFIANÇA',72),@('FONTE',140))){$column=New-Object Windows.Forms.DataGridViewTextBoxColumn;$column.HeaderText=$spec[0];$column.Width=$spec[1];$column.ReadOnly=$true;[void]$grid.Columns.Add($column)}
    foreach($match in $Matches){$track=$match.Track;$suggestion=$match.Suggestion;$current="$($track.Artist) — $($track.Title) | $($track.Album) | $($track.Genre) | $($track.Year)";$proposed="$($suggestion.Artist) — $($suggestion.Title) | $($suggestion.Album) | $($suggestion.Genre) | $($suggestion.Year)";$rowValues=New-Object object[] 6;$rowValues[0]=([int]$suggestion.Confidence -ge [int]$script:Settings.InternetMetadata.MinimumConfidence);$rowValues[1]=[string]$track.Name;$rowValues[2]=[string]$current;$rowValues[3]=[string]$proposed;$rowValues[4]="$($suggestion.Confidence)%";$rowValues[5]=[string]$suggestion.Source;$index=$grid.Rows.Add($rowValues);$grid.Rows[$index].Tag=$match}
    $bottom=New-Object Windows.Forms.Panel;$bottom.Dock='Bottom';$bottom.Height=52;$bottom.BackColor=[Drawing.Color]::FromArgb(195,195,195)
    $replace=New-Object Windows.Forms.CheckBox;$replace.Text='Também substituir campos já preenchidos';$replace.Left=12;$replace.Top=16;$replace.Width=250;$replace.ForeColor=[Drawing.Color]::Black;$bottom.Controls.Add($replace)
    $write=New-Object Windows.Forms.CheckBox;$write.Text='Gravar tags aprovadas nos arquivos (com histórico e undo)';$write.Left=275;$write.Top=16;$write.Width=360;$write.Checked=[bool]$script:Settings.InternetMetadata.WriteApprovedTags;$write.ForeColor=[Drawing.Color]::Black;$bottom.Controls.Add($write)
    $apply=New-Object Windows.Forms.Button;$apply.Text='Usar dados marcados';$apply.Left=800;$apply.Top=10;$apply.Width=160;$apply.Height=32;$apply.DialogResult='OK';$bottom.Controls.Add($apply)
    $cancel=New-Object Windows.Forms.Button;$cancel.Text='Cancelar';$cancel.Left=968;$cancel.Top=10;$cancel.Width=110;$cancel.Height=32;$cancel.DialogResult='Cancel';$bottom.Controls.Add($cancel)
    $intro=New-Object Windows.Forms.Panel;$intro.Dock='Top';$intro.Height=48;$intro.BackColor=[Drawing.Color]::FromArgb(214,214,214)
    $introText=New-Object Windows.Forms.Label;$introText.Dock='Fill';$introText.Padding=New-Object Windows.Forms.Padding(10,7,10,5);$introText.Text="Confira os dados encontrados e marque somente o que deseja usar.`r`nOs arquivos só serão alterados se a opção de gravar tags estiver marcada.";$introText.ForeColor=[Drawing.Color]::Black;$intro.Controls.Add($introText)
    $form.Controls.Add($grid);$form.Controls.Add($bottom);$form.Controls.Add($intro);$form.AcceptButton=$apply;$form.CancelButton=$cancel;Set-CrivoFormStyle -Form $form -Title 'Revisar dados encontrados online'
    if($form.ShowDialog() -ne [Windows.Forms.DialogResult]::OK){return}
    $approved=New-Object Collections.Generic.List[object]
    foreach($row in $grid.Rows){if([bool]$row.Cells[0].Value){$item=$row.Tag;if(Set-TrackSuggestion -Track $item.Track -Suggestion $item.Suggestion -FillOnlyEmpty:(-not$replace.Checked)){$approved.Add($item.Track)}}}
    if(-not$approved.Count){Show-Message 'Nenhum dado encontrado foi marcado para uso.' 'Buscar dados ausentes';return}
    $tagSummary='';if($write.Checked){$tagResult=Write-ApprovedMetadata -Tracks $approved.ToArray();$tagSummary="`nTags gravadas: $($tagResult.Updated)`nErros de gravação: $($tagResult.Errors)`nBackup registrado no histórico."}
    foreach($track in $approved){Update-TrackMetadataStatus -Track $track};Update-Dashboard;if($script:DestinationChosen){Invalidate-Plan}else{$PreviewGrid.Items.Refresh()};Show-Message "Dados aplicados em $($approved.Count) faixa(s).$tagSummary" 'Dados das faixas atualizados'
}

function Invoke-OnlineEnrichment {
    if(-not$script:Tracks.Count){Show-Message 'Escolha e analise uma pasta primeiro.';return}
    $candidates=@($script:Tracks|Where-Object{$_.Selected -and ($_.MissingTitle -or -not$_.Artist -or -not$_.Album -or $_.MissingGenre -or -not$_.Year)})
    if(-not$candidates.Count){Show-Message 'As faixas selecionadas já possuem título, artista, álbum, gênero e ano.' 'Buscar dados ausentes';return}
    $estimated=[Math]::Ceiling($candidates.Count*2.2/60)
    if(-not(Show-CrivoConfirm -Message "Buscar automaticamente título, artista, álbum, gênero e ano ausentes de $($candidates.Count) track(s)?`n`nVocê revisará os resultados antes de aplicar. Nenhum arquivo será alterado nesta etapa.`nTempo estimado: $estimated minuto(s). O áudio não será enviado." -Title 'Buscar dados ausentes automaticamente' -ConfirmText 'BUSCAR')){return}
    $matches=New-Object Collections.Generic.List[object];$EnrichMetadataButton.IsEnabled=$false
    try{
        for($i=0;$i -lt$candidates.Count;$i++){$track=$candidates[$i];Update-TrackMetadataStatus -Track $track -Override 'Buscando dados automaticamente…';Set-Status "Buscando dados: $($track.Name) ($($i+1) de $($candidates.Count))" ([int](($i+1)/$candidates.Count*100));$suggestion=Get-OnlineMetadataSuggestion -Track $track -Settings $script:Settings;if($suggestion.Found){Update-TrackMetadataStatus -Track $track -Override 'Dados encontrados — revise antes de aplicar';$matches.Add([pscustomobject]@{Track=$track;Suggestion=$suggestion})}else{Update-TrackMetadataStatus -Track $track -Override 'Não encontrado automaticamente — edite manualmente na lista'}}
        Set-Status "Busca concluída — dados encontrados para $($matches.Count) faixa(s)" 100
        $PreviewGrid.Items.Refresh();Refresh-PreviewFilter
        if($matches.Count){Show-MetadataReview -Matches $matches.ToArray()}else{Show-Message 'Nenhum dado foi encontrado automaticamente. Selecione uma track na lista e use Editar dados faltantes para preencher manualmente.' 'Busca automática concluída'}
    }catch{Write-AppLog -Message $_.Exception.ToString() -Level ERROR;Show-Message $_.Exception.Message 'Falha ao buscar dados online' Error;Set-Status 'Falha ao buscar dados das faixas' 0}
    finally{$EnrichMetadataButton.IsEnabled=$true}
}

function Get-ODTInboxPath {
    if($script:Settings.PSObject.Properties['Acquisition'] -and $script:Settings.Acquisition.InboxPath){return [Environment]::ExpandEnvironmentVariables([string]$script:Settings.Acquisition.InboxPath)}
    return Join-Path $AppRoot 'Inbox'
}

function Get-ODTDownloadPath {
    if($script:Settings.PSObject.Properties['Acquisition'] -and $script:Settings.Acquisition.PSObject.Properties['DownloadPath'] -and $script:Settings.Acquisition.DownloadPath){
        return [Environment]::ExpandEnvironmentVariables([string]$script:Settings.Acquisition.DownloadPath)
    }
    return Join-Path (Get-ODTInboxPath) 'Pending'
}

function Open-ODTInbox {
    $root=Get-ODTInboxPath;Initialize-ODTInbox -Root $root|Out-Null;Start-Process explorer.exe -ArgumentList "`"$root`""
}

function Import-ODTInbox {
    $path=Get-ODTDownloadPath;[IO.Directory]::CreateDirectory($path)|Out-Null;$files=@(Get-ChildItem -LiteralPath $path -File -ErrorAction SilentlyContinue|Where-Object Extension -in @('.mp3','.wav','.flac','.aiff','.aif','.m4a','.aac','.ogg','.wma'))
    if(-not$files.Count){
        $otherFolders=@($script:DownloadQueue|Where-Object{$_.Status -eq 'Concluido' -and $_.PSObject.Properties['FinalPath'] -and $_.FinalPath -and (Test-Path -LiteralPath $_.FinalPath -PathType Leaf)}|ForEach-Object{Split-Path -Parent ([string]$_.FinalPath)}|Where-Object{$_ -and $_ -ne $path}|Select-Object -Unique)
        $where=if($otherFolders.Count){"`n`nHá downloads concluídos em outro destino:`n"+($otherFolders -join "`n")+"`n`nAltere a pasta acima ou baixe novamente para o destino atual."}else{"`n`nBaixe ou copie as faixas para:`n$path"}
        Show-Message ("Nenhuma track de áudio foi encontrada no destino selecionado:$([Environment]::NewLine)$path"+$where) 'Inbox de downloads';return $false
    }
    Load-SourceFolder -Path $path;return $true
}

function Update-DownloadStatus {
    try {
        $path=Get-ODTDownloadPath;[IO.Directory]::CreateDirectory($path)|Out-Null;$audio=@(Get-ChildItem -LiteralPath $path -File -ErrorAction SilentlyContinue|Where-Object Extension -in @('.mp3','.wav','.flac','.aiff','.aif','.m4a','.aac','.ogg','.wma')).Count
        $script:DownloadFolderTrackCount=$audio
        $active=@($script:DownloadQueue|Where-Object{$_.Status -in @('Baixando','Analisando','Expandindo','Pendente')}).Count;$done=@($script:DownloadQueue|Where-Object{$_.Status -eq 'Concluido'}).Count;$failed=@($script:DownloadQueue|Where-Object{$_.Status -in @('Falhou','Link privado')}).Count
        $DownloadStatusText.Text="Pasta de downloads: $audio track(s) • fila: $active em andamento, $done concluída(s), $failed falha(s)."
    } catch { $script:DownloadFolderTrackCount=0;$DownloadStatusText.Text='Pasta de downloads ainda não disponível.' }
}

function Update-ContextInformation {
    switch([int]$MainTabs.SelectedIndex){
        0 {
            Update-DownloadStatus
            $active=@($script:DownloadQueue|Where-Object{$_.Status -in @('Baixando','Analisando','Expandindo','Pendente')}).Count
            $StatusText.Text="BAIXAR • $($script:DownloadFolderTrackCount) TRACK(S) NA PASTA • $active EM ANDAMENTO"
        }
        1 {
            Update-Dashboard
            if(-not(Test-Path -LiteralPath $SourceText.Text -PathType Container)){$StatusText.Text='ORGANIZAR • ESCOLHA A PASTA DE ORIGEM'}
            elseif(-not$script:DestinationChosen){$StatusText.Text="ORGANIZAR • $($script:Tracks.Count) TRACK(S) ANALISADAS • ESCOLHA O DESTINO"}
            elseif(-not$script:Plan){$StatusText.Text="ORGANIZAR • $($script:Tracks.Count) TRACK(S) ANALISADAS • RECALCULANDO PLANO"}
            else{$ready=@($script:Plan.Items|Where-Object Status -eq 'Ready').Count;$StatusText.Text="ORGANIZAR • $($script:Tracks.Count) TRACK(S) ANALISADAS • $ready PRONTA(S)"}
        }
        2 {
            if($script:RekordboxAudit){$StatusText.Text="AUDITORIA • $($script:RekordboxAudit.Total) TRACK(S) • $($script:RekordboxAudit.Problems) PROBLEMA(S) ENCONTRADO(S)"}
            elseif($script:AuditMode -eq 'Usb'){$StatusText.Text='AUDITORIA • ESCOLHA O PENDRIVE E CLIQUE EM VERIFICAR'}
            else{$StatusText.Text='AUDITORIA • CLIQUE EM ESCANEAR BIBLIOTECA'}
        }
        3 {
            if($script:UsbHealthReport){$StatusText.Text="KIT DE FERRAMENTAS USB • $($script:UsbHealthReport.Overall.ToUpperInvariant())"}
            else{$StatusText.Text='KIT DE FERRAMENTAS USB • ESCOLHA UM DISPOSITIVO PARA O DIAGNÓSTICO SOMENTE LEITURA'}
        }
    }
}

function Get-ODTDownloaderPath {
    $configured=[string]$script:Settings.Acquisition.DownloaderPath;if([IO.Path]::IsPathRooted($configured)){return $configured};return Join-Path $AppRoot $configured
}

function Get-ODTSpotifyResolverPath {
    $configured=if($script:Settings.Acquisition.PSObject.Properties['SpotifyResolverPath']){[string]$script:Settings.Acquisition.SpotifyResolverPath}else{'Tools\spotdl.exe'}
    if([IO.Path]::IsPathRooted($configured)){return $configured};return Join-Path $AppRoot $configured
}

function Get-ODTFFmpegPath {
    $bundled=Join-Path $AppRoot 'Tools\ffmpeg.exe'
    if(Test-Path -LiteralPath $bundled -PathType Leaf){return $bundled}
    $configured=[Environment]::ExpandEnvironmentVariables([string]$script:Settings.Acquisition.FFmpegPath)
    if(-not$configured){return ''}
    if([IO.Path]::IsPathRooted($configured)){return $configured}
    return Join-Path $AppRoot $configured
}

function Get-ODTEnvironmentChecks {
    param([switch]$IncludeInternet)
    $checks=New-Object Collections.Generic.List[object]
    foreach($tool in @(
        @('Downloader',$(Get-ODTDownloaderPath),$true),
        @('FFmpeg',$(Get-ODTFFmpegPath),$true),
        @('Spotify',$(Get-ODTSpotifyResolverPath),$false)
    )){$ok=[bool](Test-Path -LiteralPath ([string]$tool[1]) -PathType Leaf);$checks.Add([pscustomobject]@{Name=[string]$tool[0];Ok=$ok;Required=[bool]$tool[2];Detail=$(if($ok){'disponível'}else{'não encontrado'})})}
    $downloadOk=$false;$downloadDetail='não gravável'
    try{$downloadPath=Get-ODTDownloadPath;[IO.Directory]::CreateDirectory($downloadPath)|Out-Null;$probe=Join-Path $downloadPath ('.crivo-write-'+[guid]::NewGuid().ToString('N')+'.tmp');[IO.File]::WriteAllText($probe,'ok');[IO.File]::Delete($probe);$downloadOk=$true;$downloadDetail='pasta gravável'}catch{$downloadDetail=$_.Exception.Message}
    $checks.Add([pscustomobject]@{Name='Pasta de downloads';Ok=$downloadOk;Required=$true;Detail=$downloadDetail})
    $rbExe='';$configured='';if($script:Settings.PSObject.Properties['Rekordbox'] -and $script:Settings.Rekordbox.PSObject.Properties['ExecutablePath']){$configured=[Environment]::ExpandEnvironmentVariables([string]$script:Settings.Rekordbox.ExecutablePath)}
    $rbCandidates=@($configured,"$env:ProgramFiles\rekordbox\rekordbox.exe","$env:ProgramFiles\Pioneer\rekordbox 7\rekordbox.exe","$env:ProgramFiles\AlphaTheta\rekordbox 7\rekordbox.exe","${env:ProgramFiles(x86)}\Pioneer\rekordbox\rekordbox.exe")
    $rbExe=@($rbCandidates|Where-Object{$_ -and (Test-Path -LiteralPath $_ -PathType Leaf)}|Select-Object -First 1);$checks.Add([pscustomobject]@{Name='Rekordbox';Ok=[bool]$rbExe.Count;Required=$false;Detail=$(if($rbExe.Count){'executável encontrado'}else{'opcional: não localizado'})})
    try{$database=Get-RekordboxDatabasePath;$databaseOk=Test-Path -LiteralPath $database -PathType Leaf}catch{$databaseOk=$false};$checks.Add([pscustomobject]@{Name='Banco do Rekordbox';Ok=[bool]$databaseOk;Required=$false;Detail=$(if($databaseOk){'base encontrada'}else{'opcional: base não localizada'})})
    if($IncludeInternet){$internetOk=$false;try{$response=Invoke-WebRequest -UseBasicParsing -Uri 'https://musicbrainz.org/ws/2/' -Headers @{'User-Agent'='CRIVO-DJ/0.9 closed-beta'} -TimeoutSec 8;$internetOk=[bool]$response}catch{$internetOk=[bool]$_.Exception.PSObject.Properties['Response']};$checks.Add([pscustomobject]@{Name='Internet';Ok=$internetOk;Required=$true;Detail=$(if($internetOk){'conexão disponível'}else{'sem resposta'})})}
    return $checks.ToArray()
}

function Update-ODTEnvironmentStatus {
    $checks=@(Get-ODTEnvironmentChecks);$requiredFailures=@($checks|Where-Object{$_.Required -and -not$_.Ok}).Count;$optionalFailures=@($checks|Where-Object{-not$_.Required -and -not$_.Ok}).Count
    if($requiredFailures){$EnvironmentStatusText.Text="AMBIENTE: $requiredFailures ITEM(NS) PRECISAM DE ATENÇÃO";$EnvironmentStatusText.Foreground='#8F1F1F'}elseif($optionalFailures){$EnvironmentStatusText.Text='AMBIENTE: CORE PRONTO • REKORDBOX OPCIONAL PENDENTE';$EnvironmentStatusText.Foreground='#6B4A00'}else{$EnvironmentStatusText.Text='AMBIENTE: PRONTO PARA USO';$EnvironmentStatusText.Foreground='#2F6655'}
    $EnvironmentStatusText.ToolTip=(@($checks|ForEach-Object{"$($_.Name): $($_.Detail)"}) -join [Environment]::NewLine)
    return $checks
}

function Show-ODTSystemCheck {
    $checks=@(Get-ODTEnvironmentChecks -IncludeInternet);$lines=@($checks|ForEach-Object{"$(if($_.Ok){'OK'}else{'ATENÇÃO'}) — $($_.Name): $($_.Detail)"});Update-ODTEnvironmentStatus|Out-Null
    $requiredFailures=@($checks|Where-Object{$_.Required -and -not$_.Ok}).Count;$summary=if($requiredFailures){"$requiredFailures requisito(s) do fluxo principal precisam de atenção."}else{'O fluxo principal está pronto para o teste fechado.'}
    Show-Message ($summary+"`n`n"+($lines -join "`n")) 'Verificação do ambiente' $(if($requiredFailures){'Warning'}else{'Info'})
}

function Export-ODTDiagnostic {
    $dialog=New-Object Windows.Forms.SaveFileDialog;$dialog.Title='Exportar diagnóstico do CRIVO DJ';$dialog.Filter='Arquivo ZIP (*.zip)|*.zip';$dialog.FileName="CRIVO-DJ-Diagnostico-$((Get-Date).ToString('yyyyMMdd-HHmm')).zip";if($dialog.ShowDialog() -ne [Windows.Forms.DialogResult]::OK){return}
    $tempRoot=Join-Path (Get-AppDataRoot) ('Diagnostics\'+[guid]::NewGuid().ToString('N'))
    try{
        [IO.Directory]::CreateDirectory($tempRoot)|Out-Null;$checks=@(Get-ODTEnvironmentChecks -IncludeInternet)
        $summary=[ordered]@{Version=$script:AppVersion;GeneratedAt=(Get-Date).ToString('o');Windows=[Environment]::OSVersion.VersionString;PowerShell=$PSVersionTable.PSVersion.ToString();Checks=$checks;ActiveTab=[string]$MainTabs.SelectedItem.Header;QueueItems=$script:DownloadQueue.Count;LoadedTracks=$script:Tracks.Count;AuditLoaded=[bool]$script:RekordboxAudit}
        Write-JsonFile -Path (Join-Path $tempRoot 'system.json') -Value $summary
        $safeSettings=[ordered]@{DuplicateLevel=[string]$script:Settings.DuplicateLevel;MissingMetadataPolicy=[string]$script:Settings.MissingMetadataPolicy;LogLevel=[string]$script:Settings.LogLevel;AudioExtensions=@($script:Settings.AudioExtensions);Quality=$script:Settings.Quality;InternetMetadata=[ordered]@{Enabled=[bool]$script:Settings.InternetMetadata.Enabled;Provider=[string]$script:Settings.InternetMetadata.Provider;MinimumConfidence=[int]$script:Settings.InternetMetadata.MinimumConfidence;HasAcoustIdKey=[bool](-not[string]::IsNullOrWhiteSpace([string]$script:Settings.InternetMetadata.AcoustIdClientKey))};Paths='omitidos por privacidade'}
        Write-JsonFile -Path (Join-Path $tempRoot 'settings-sanitized.json') -Value $safeSettings
        $logFolder=Join-Path (Get-AppDataRoot) 'Logs';foreach($log in @(Get-ChildItem -LiteralPath $logFolder -File -Filter '*.log' -ErrorAction SilentlyContinue|Sort-Object LastWriteTime -Descending|Select-Object -First 2)){$text=[IO.File]::ReadAllText($log.FullName);if($env:USERPROFILE){$text=$text.Replace($env:USERPROFILE,'%USERPROFILE%')};$text=[regex]::Replace($text,'(?i)(/s-)[A-Za-z0-9]+','$1REDACTED');$text=[regex]::Replace($text,'(?i)(https?://[^\s?]+)\?[^\s]+','$1?[PARÂMETROS_REMOVIDOS]');[IO.File]::WriteAllText((Join-Path $tempRoot $log.Name),$text,[Text.UTF8Encoding]::new($false))}
        Compress-Archive -Path (Join-Path $tempRoot '*') -DestinationPath $dialog.FileName -CompressionLevel Optimal -Force
        if(-not(Test-Path -LiteralPath $dialog.FileName -PathType Leaf) -or (Get-Item -LiteralPath $dialog.FileName).Length -le 0){throw 'O arquivo de diagnóstico não foi criado no destino escolhido.'}
        Show-Message "Diagnóstico exportado e conferido sem caminhos pessoais ou chaves:`n$($dialog.FileName)" 'Diagnóstico pronto'
    }catch{Write-AppLog -Message $_.Exception.ToString() -Level ERROR;Show-Message $_.Exception.Message 'Falha ao exportar diagnóstico' Error}finally{if(Test-Path -LiteralPath $tempRoot -PathType Container){[IO.Directory]::Delete($tempRoot,$true)}}
}

function Add-DownloadLinksToGrid {
    param([string]$Text)
    $links=New-Object Collections.Generic.List[string]
    foreach($match in [regex]::Matches([string]$Text,'https?://[^\s\x00]+')){$value=$match.Value.TrimEnd([char[]]".,;)]");if($value -and -not$links.Contains($value)){$links.Add($value)}}
    $added=0;$quality='320';$format='MP3 320 kbps';$root=Get-ODTDownloadPath;$engine=Get-ODTDownloaderPath;$spotifyEngine=Get-ODTSpotifyResolverPath;$ffmpeg=Get-ODTFFmpegPath
    foreach($url in $links){
        $exists=$false;foreach($queued in $script:DownloadQueue){if($queued.PSObject.Properties['Url'] -and [string]$queued.Url -eq $url){$exists=$true;break}}
        if($exists){continue}
        try{
            $isSpotify=$url -match '^https?://(open\.)?spotify\.com/';$isSingleSpotify=$url -match '^https?://(open\.)?spotify\.com/(?:intl-[a-z]{2}(?:-[a-z]{2})?/)?track/';$isYouTubeTrack=$url -match '(youtube\.com/watch\?|youtu\.be/)';$isSoundCloudUserPage=$url -match '^https?://(?:www\.)?soundcloud\.com/[\w-]+/?(?:[?#].*)?$';$isPlaylist=(-not$isYouTubeTrack -and $url -match '([?&]list=|/playlist(?:s)?/|/sets?/|/albums?/|/mix(?:es)?/|/collection/|/tracklist/|/shows?/|/channels?/|/series/|/feed/)') -or $isSoundCloudUserPage;$singleTrack=(-not$isPlaylist)
            $resolver=if($isSpotify) { Start-ODTSpotifyResolver -Url $url -OutputRoot $root -EnginePath $spotifyEngine -FFmpegPath $ffmpeg -Quality '320' } else { Start-ODTPlaylistResolver -Url $url -OutputRoot $root -EnginePath $engine -Quality '320' -SingleTrack:$singleTrack }
            if($isSingleSpotify -or -not$isPlaylist){$resolver.Title='Lendo dados da track...';$resolver.Detail='Buscando título, artista e capa';$resolver.TimeoutSeconds=90}elseif($url -match '(?i)/discover/sets/personalized-tracks'){$resolver.Title='Lendo playlist personalizada...';$resolver.Detail='Usando a sessão local do navegador para separar as tracks'}else{$resolver.Title='Lendo playlist...';$resolver.Detail='Separando a playlist em tracks'}
            $script:DownloadQueue.Add($resolver);$added++
        }catch{
            try{$uri=[Uri]$url;$source=$uri.Host -replace '^www\.','';$leaf=[Uri]::UnescapeDataString($uri.Segments[$uri.Segments.Count-1]).Trim('/');$label=($leaf -replace '[-_]+',' ').Trim()}catch{$source='Link';$label=''}
            $title=if($label){$label}else{'Link pronto para analisar'};$script:DownloadQueue.Add([pscustomobject]@{Kind='LinkRequest';IsSelected=$true;Title=$title;Source=$source;Duration='';Thumbnail='';Url=$url;DownloadUrl=$url;Quality=$format;QualityCode=$quality;Status='Pronto';Progress='';ProgressValue=0;Detail='Clique em Iniciar download';Process=$null;OutputFolder=$root});$added++
        }
    }
    if($added){$DownloadQueueGrid.Items.Refresh();$DownloadStatusText.Text="$added link(s) recebido(s). Buscando capas e separando tracks…";if($script:DownloadTimer){$script:DownloadTimer.Start()}}
    return $added
}

function Start-DownloadUrls {
    try{[void](Add-DownloadLinksToGrid -Text $DownloadUrlText.Text);$DownloadUrlText.Clear();$currentRoot=Get-ODTDownloadPath
        if(-not(Test-Path -LiteralPath $currentRoot -PathType Container)){[IO.Directory]::CreateDirectory($currentRoot)|Out-Null}
        # O destino pode ser trocado depois que os links entram na lista. Tudo
        # que ainda não começou deve acompanhar o caminho exibido na tela.
        foreach($queued in $script:DownloadQueue){if($queued.Status -in @('Pronto','Pendente','Analisando','Expandindo')){if($queued.PSObject.Properties['OutputFolder']){$queued.OutputFolder=$currentRoot}else{$queued|Add-Member NoteProperty OutputFolder $currentRoot}}}
        $ready=@($script:DownloadQueue|Where-Object{$_.Status -eq 'Pronto' -and $_.IsSelected});$analyzing=@($script:DownloadQueue|Where-Object{$_.Status -in @('Analisando','Expandindo')}).Count
        if(-not$ready.Count -and -not$analyzing){$script:DownloadStartRequested=$false;Show-Message 'Marque na lista pelo menos uma track pronta para baixar.' 'Baixar tracks';return}
        $script:DownloadStartRequested=$true
        foreach($request in $ready){$request.QualityCode='320';$request.Quality='MP3 320 kbps';$request.Status='Pendente';$request.Progress='0%';$request.ProgressValue=0;$request.Detail='Aguardando vaga para baixar'}
        $DownloadQueueGrid.Items.Refresh();$DownloadStatusText.Text=$(if($analyzing){'Análise em andamento; as tracks selecionadas iniciarão assim que os dados chegarem.'}else{"$($ready.Count) track(s) adicionada(s) à fila de download."});$script:DownloadTimer.Start()
    }catch{Write-AppLog -Message $_.Exception.ToString() -Level ERROR;Show-Message $_.Exception.Message 'Não foi possível adicionar o link' Error}
}

function Sync-PendingDownloadDestination {
    param([Parameter(Mandatory)][string]$Path)
    $updated=0
    foreach($queued in $script:DownloadQueue){
        if($queued.Status -notin @('Pronto','Pendente','Analisando','Expandindo')){continue}
        if($queued.PSObject.Properties['OutputFolder']){$queued.OutputFolder=$Path}else{$queued|Add-Member NoteProperty OutputFolder $Path}
        $updated++
    }
    $DownloadQueueGrid.Items.Refresh()
    return $updated
}

function Add-DroppedDownloadLinks {
    param($EventArgs)
    try{$text='';foreach($format in @([Windows.DataFormats]::UnicodeText,[Windows.DataFormats]::Text,'UniformResourceLocatorW','UniformResourceLocator')){if($EventArgs.Data.GetDataPresent($format)){try{$data=$EventArgs.Data.GetData($format);if($data -is [IO.MemoryStream]){$reader=New-Object IO.StreamReader($data,[Text.Encoding]::Unicode);$text=$reader.ReadToEnd();$reader.Dispose()}else{$text=[string]$data};if($text){break}}catch{}}};if($text){[void](Add-DownloadLinksToGrid -Text $text)}}catch{Write-AppLog -Message $_.Exception.ToString() -Level ERROR;Show-Message $_.Exception.Message 'Não foi possível interpretar o link arrastado' Error}
}

function Remove-SelectedDownloadsFromGrid {
    $selected=@($DownloadQueueGrid.SelectedItems);if(-not$selected.Count){Show-Message 'Destaque uma ou mais linhas da lista para remover.' 'Remover da fila';return}
    $removed=0;$blocked=0;foreach($item in $selected){if($item.Status -in @('Baixando','Analisando','Expandindo','Pendente')){$blocked++;continue};if($script:DownloadQueue.Remove($item)){$removed++}}
    $DownloadQueueGrid.Items.Refresh();$DownloadStatusText.Text="$removed item(ns) removido(s) da fila.";if($blocked){Show-Message "$blocked item(ns) estão em processamento e não foram removidos." 'Remover da fila'}
}

function Import-RekordboxMetadataFile {
    if(-not$script:Tracks.Count){Show-Message 'Escolha e analise uma pasta antes de importar o XML do Rekordbox.' 'Rekordbox';return}
    $dialog=New-Object Windows.Forms.OpenFileDialog;$dialog.Title='Importar XML do Rekordbox';$dialog.Filter='Rekordbox XML (*.xml)|*.xml|Todos os arquivos (*.*)|*.*'
    if($dialog.ShowDialog() -ne [Windows.Forms.DialogResult]::OK){return}
    try{$result=Import-RekordboxXmlMetadata -Path $dialog.FileName -Tracks $script:Tracks;$PreviewGrid.Items.Refresh();Update-Dashboard;if($script:DestinationChosen){Invalidate-Plan};Show-Message "XML lido sem alterar o arquivo original.`n`nFaixas analisadas: $($result.Tracks)`nCorrespondências atualizadas: $($result.Matched)" 'Rekordbox'}catch{Show-Message $_.Exception.Message 'Falha ao importar Rekordbox XML' Error}
}

function Export-RekordboxCollection {
    if(-not$script:Tracks.Count){Show-Message 'Escolha e analise uma pasta antes de exportar para o Rekordbox.' 'Rekordbox';return}
    $dialog=New-Object Windows.Forms.SaveFileDialog;$dialog.Title='Exportar coleção para o Rekordbox';$dialog.Filter='Rekordbox XML (*.xml)|*.xml';$dialog.FileName='CRIVO-DJ-Rekordbox.xml'
    if($dialog.ShowDialog() -ne [Windows.Forms.DialogResult]::OK){return}
    $playlistName='CRIVO DJ — Organizado';if($OrganizerPlaylistNameText -and -not[string]::IsNullOrWhiteSpace($OrganizerPlaylistNameText.Text)){$playlistName=$OrganizerPlaylistNameText.Text.Trim()}
    try{Export-RekordboxXml -Tracks $script:Tracks -Path $dialog.FileName -PlaylistName $playlistName|Out-Null;Show-Message "Playlist '$playlistName' preparada para o Rekordbox.`n`nO XML original não foi sobrescrito. No Rekordbox, selecione este arquivo em Preferências > Avançado > Database > Imported Library e arraste a playlist para Playlists." 'Enviar ao Rekordbox'}catch{Show-Message $_.Exception.Message 'Falha ao exportar Rekordbox XML' Error}
}

function Get-RekordboxDatabasePath {
    if($script:Settings.PSObject.Properties['Rekordbox'] -and $script:Settings.Rekordbox.PSObject.Properties['DatabasePath']){
        $configured=[Environment]::ExpandEnvironmentVariables([string]$script:Settings.Rekordbox.DatabasePath)
        if(Test-Path -LiteralPath $configured -PathType Leaf){return $configured}
    }
    $standard=Join-Path $env:APPDATA 'Pioneer\rekordbox\master.db'
    if(Test-Path -LiteralPath $standard -PathType Leaf){return $standard}
    throw 'O master.db do Rekordbox não foi localizado.'
}

function Wait-CRIVOHelperProcess {
    param([Parameter(Mandatory)]$Process,[int]$TimeoutSeconds=120)
    if(-not$Process.WaitForExit($TimeoutSeconds*1000)){try{$Process.Kill();$Process.WaitForExit()}catch{};throw "A integração excedeu $TimeoutSeconds segundos e foi encerrada com segurança."}
    $Process.WaitForExit();$Process.Refresh()
}

function Get-RekordboxDatabaseLibrary {
    param([Parameter(Mandatory)][string]$Path)
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "Banco do Rekordbox não encontrado: $Path"}
    $helper=Join-Path $AppRoot 'Tools\ODT-RekordboxDirect\ODT-RekordboxDirect.exe'
    if(-not(Test-Path -LiteralPath $helper -PathType Leaf)){throw "Helper Pyrekordbox não encontrado: $helper"}
    $token=[Guid]::NewGuid().ToString('N');$payloadPath=Join-Path ([IO.Path]::GetTempPath()) "CRIVO-Audit-$token.json";$stdout=Join-Path ([IO.Path]::GetTempPath()) "CRIVO-Audit-$token.out";$stderr=Join-Path ([IO.Path]::GetTempPath()) "CRIVO-Audit-$token.err"
    try{
        [IO.File]::WriteAllText($payloadPath,(@{operation='audit';databasePath=$Path}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
        $process=Start-Process -FilePath $helper -ArgumentList @("`"$payloadPath`"") -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr;Wait-CRIVOHelperProcess -Process $process -TimeoutSeconds 120
        $output=if(Test-Path -LiteralPath $stdout){[IO.File]::ReadAllText($stdout,[Text.Encoding]::UTF8).Trim()}else{''};$errorOutput=if(Test-Path -LiteralPath $stderr){[IO.File]::ReadAllText($stderr,[Text.Encoding]::UTF8).Trim()}else{''}
        $result=$null;if($output){try{$result=$output|ConvertFrom-Json}catch{}}
        $helperSucceeded=[bool]($result -and $result.PSObject.Properties['success'] -and [bool]$result.success)
        $exitCode=$null;try{if($null -ne $process.ExitCode){$exitCode=[int]$process.ExitCode}}catch{}
        if(($null -ne $exitCode -and $exitCode -ne 0) -or -not$helperSucceeded){
            $codeLabel=if($null -eq $exitCode){'indisponível'}else{[string]$exitCode}
            $message=if($result -and $result.PSObject.Properties['message'] -and $result.message){[string]$result.message}elseif($errorOutput){$errorOutput}elseif($output){"O Pyrekordbox encerrou com código $codeLabel e devolveu uma resposta sem mensagem de erro."}else{'O Pyrekordbox não retornou uma leitura válida.'}
            throw $message
        }
        $tracks=New-Object Collections.Generic.List[object];$byId=@{}
        foreach($track in @($result.tracks)){
            $location=[string]$track.location;$exists=[bool]($location -and (Test-Path -LiteralPath $location -PathType Leaf))
            $artwork=[string]$track.artworkPath;if($artwork){$artwork=Join-Path (Join-Path (Split-Path -Parent $Path) 'share') $artwork.TrimStart('/','\')}
            $item=[pscustomobject]@{TrackID=[string]$track.trackID;Name=[string]$track.name;Artist=[string]$track.artist;Album=[string]$track.album;Genre=[string]$track.genre;Year=$(if($track.PSObject.Properties['year']){[string]$track.year}else{''});Bpm=[string]$track.bpm;Key=[string]$track.key;Bitrate=$(if($track.PSObject.Properties['bitrate']){[int]$track.bitrate}else{0});SampleRate=$(if($track.PSObject.Properties['sampleRate']){[int]$track.sampleRate}else{0});FileSize=$(if($track.PSObject.Properties['fileSize']){[int64]$track.fileSize}else{0});Duration=$(if($track.PSObject.Properties['duration']){[int]$track.duration}else{0});FileType=$(if($track.PSObject.Properties['fileType']){[int]$track.fileType}else{0});Rating='';Comments='';Location=$location;Exists=$exists;PlaylistCount=[int]$track.playlistCount;PlaylistNames=@($track.playlists);Analysis=[string]$track.analysis;ArtworkPath=$artwork};$tracks.Add($item);if($item.TrackID){$byId[$item.TrackID]=$item}
        }
        $playlists=New-Object Collections.Generic.List[object];foreach($playlist in @($result.playlists)){$playlists.Add([pscustomobject]@{Name=[string]$playlist.name;Path=[string]$playlist.path;TrackCount=[int]$playlist.trackCount;TrackIDs=@($playlist.trackIDs)})}
        return [pscustomobject]@{Path=$Path;Product=[string]$result.product;Version='Database';Tracks=$tracks.ToArray();Playlists=$playlists.ToArray();TracksById=$byId}
    }finally{foreach($temporary in @($payloadPath,$stdout,$stderr)){if(Test-Path -LiteralPath $temporary -PathType Leaf){[IO.File]::Delete($temporary)}}}
}

function Restore-RekordboxDatabaseBackup {
    param([Parameter(Mandatory)][string]$DatabaseDirectory,[Parameter(Mandatory)][string]$BackupDirectory)
    foreach($name in @('master.db','master.db-wal','master.db-shm','masterPlaylists6.xml','master.backup.db')){
        $current=Join-Path $DatabaseDirectory $name;$saved=Join-Path $BackupDirectory $name
        if(Test-Path -LiteralPath $current -PathType Leaf){[IO.File]::Delete($current)}
        if(Test-Path -LiteralPath $saved -PathType Leaf){[IO.File]::Copy($saved,$current,$true)}
    }
}

function Write-RekordboxPlaylistDirect {
    param([Parameter(Mandatory)][object[]]$Tracks,[Parameter(Mandatory)][string]$PlaylistName)
    $running=@(Get-Process -Name 'rekordbox' -ErrorAction SilentlyContinue)
    if($running.Count){throw 'Feche a janela do Rekordbox antes da gravação direta.'}
    $agents=@(Get-Process -Name 'rekordboxAgent' -ErrorAction SilentlyContinue)
    if($agents.Count){foreach($agent in $agents){try{Stop-Process -Id $agent.Id -Force -ErrorAction Stop}catch{}};Start-Sleep -Milliseconds 700}
    if(@(Get-Process -Name 'rekordboxAgent' -ErrorAction SilentlyContinue).Count){throw 'O rekordboxAgent continuou ativo. Encerre-o pelo Gerenciador de Tarefas e tente novamente.'}
    $helper=Join-Path $AppRoot 'Tools\ODT-RekordboxDirect\ODT-RekordboxDirect.exe'
    if(-not(Test-Path -LiteralPath $helper -PathType Leaf)){throw "Helper de integração direta não encontrado: $helper"}
    $database=Get-RekordboxDatabasePath;$databaseDirectory=Split-Path -Parent $database
    $backupDirectory=Join-Path (Get-AppDataRoot) ("Backups\Rekordbox\"+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'));[IO.Directory]::CreateDirectory($backupDirectory)|Out-Null
    foreach($name in @('master.db','master.db-wal','master.db-shm','masterPlaylists6.xml','master.backup.db')){$source=Join-Path $databaseDirectory $name;if(Test-Path -LiteralPath $source -PathType Leaf){[IO.File]::Copy($source,(Join-Path $backupDirectory $name),$true)}}
    $trackPayload=New-Object Collections.Generic.List[object]
    foreach($track in $Tracks){
        $trackPayload.Add([ordered]@{path=[string]$track.FullName;title=[string]$track.Title;artist=[string]$track.Artist;album=[string]$track.Album;genre=[string]$track.Genre;bpm=$(if($track.Bpm){[double]$track.Bpm}else{0});key=[string]$track.Key;year=[string]$track.Year;bitrate=$(if($track.Bitrate){[int]$track.Bitrate}else{0});sampleRate=$(if($track.SampleRate){[int]$track.SampleRate}else{0})})
    }
    $payload=[ordered]@{databasePath=$database;playlistName=$PlaylistName;tracks=$trackPayload.ToArray()}
    $token=[Guid]::NewGuid().ToString('N');$payloadPath=Join-Path ([IO.Path]::GetTempPath()) "ODT-Rekordbox-$token.json";$stdout=Join-Path ([IO.Path]::GetTempPath()) "ODT-Rekordbox-$token.out";$stderr=Join-Path ([IO.Path]::GetTempPath()) "ODT-Rekordbox-$token.err"
    try{
        [IO.File]::WriteAllText($payloadPath,($payload|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
        Set-Status 'Criando playlist diretamente no banco do Rekordbox…' 96
        $process=Start-Process -FilePath $helper -ArgumentList @("`"$payloadPath`"") -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr;Wait-CRIVOHelperProcess -Process $process -TimeoutSeconds 180
        $output=if(Test-Path -LiteralPath $stdout){[IO.File]::ReadAllText($stdout,[Text.Encoding]::UTF8).Trim()}else{''};$errorOutput=if(Test-Path -LiteralPath $stderr){[IO.File]::ReadAllText($stderr,[Text.Encoding]::UTF8).Trim()}else{''}
        $result=$null;if($output){try{$result=$output|ConvertFrom-Json}catch{}}
        $helperSucceeded=[bool]($result -and $result.PSObject.Properties['success'] -and [bool]$result.success)
        $exitCode=$null;try{if($null -ne $process.ExitCode){$exitCode=[int]$process.ExitCode}}catch{}
        if(($null -ne $exitCode -and $exitCode -ne 0) -or -not$helperSucceeded){$codeLabel=if($null -eq $exitCode){'indisponível'}else{[string]$exitCode};$message=if($result -and $result.PSObject.Properties['message'] -and $result.message){[string]$result.message}elseif($errorOutput){$errorOutput}elseif($output){"O helper encerrou com código $codeLabel e devolveu uma resposta sem mensagem de erro."}else{'O helper não retornou um resultado válido.'};throw $message}
        $result|Add-Member NoteProperty BackupPath $backupDirectory -Force;Set-Status 'Playlist gravada diretamente no Rekordbox' 100;return $result
    }catch{
        try{Restore-RekordboxDatabaseBackup -DatabaseDirectory $databaseDirectory -BackupDirectory $backupDirectory}catch{Write-AppLog -Message "Falha ao restaurar backup do Rekordbox: $($_.Exception.Message)" -Level ERROR}
        throw "A gravação direta falhou e o backup foi restaurado.`n$($_.Exception.Message)`nBackup: $backupDirectory"
    }finally{
        foreach($temporary in @($payloadPath,$stdout,$stderr)){if(Test-Path -LiteralPath $temporary -PathType Leaf){[IO.File]::Delete($temporary)}}
    }
}

function Write-RekordboxMetadataDirect {
    param([Parameter(Mandatory)][string]$TrackID,[Parameter(Mandatory)]$Metadata)
    if(@(Get-Process -Name 'rekordbox' -ErrorAction SilentlyContinue).Count){throw 'Feche a janela do Rekordbox antes de salvar os metadados.'}
    $agents=@(Get-Process -Name 'rekordboxAgent' -ErrorAction SilentlyContinue)
    if($agents.Count){foreach($agent in $agents){try{Stop-Process -Id $agent.Id -Force -ErrorAction Stop}catch{}};Start-Sleep -Milliseconds 700}
    if(@(Get-Process -Name 'rekordboxAgent' -ErrorAction SilentlyContinue).Count){throw 'O rekordboxAgent continuou ativo. Encerre-o pelo Gerenciador de Tarefas e tente novamente.'}
    $helper=Join-Path $AppRoot 'Tools\ODT-RekordboxDirect\ODT-RekordboxDirect.exe'
    if(-not(Test-Path -LiteralPath $helper -PathType Leaf)){throw "Helper de integração direta não encontrado: $helper"}
    $database=Get-RekordboxDatabasePath;$databaseDirectory=Split-Path -Parent $database
    $backupDirectory=Join-Path (Get-AppDataRoot) ("Backups\Rekordbox\"+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'));[IO.Directory]::CreateDirectory($backupDirectory)|Out-Null
    foreach($name in @('master.db','master.db-wal','master.db-shm','masterPlaylists6.xml','master.backup.db')){$source=Join-Path $databaseDirectory $name;if(Test-Path -LiteralPath $source -PathType Leaf){[IO.File]::Copy($source,(Join-Path $backupDirectory $name),$true)}}
    $payload=[ordered]@{operation='update_metadata';databasePath=$database;trackID=$TrackID;metadata=[ordered]@{title=[string]$Metadata.Title;artist=[string]$Metadata.Artist;album=[string]$Metadata.Album;genre=[string]$Metadata.Genre;year=[string]$Metadata.Year;bpm=$Metadata.Bpm;key=[string]$Metadata.Key}}
    $token=[Guid]::NewGuid().ToString('N');$payloadPath=Join-Path ([IO.Path]::GetTempPath()) "CRIVO-Metadata-$token.json";$stdout=Join-Path ([IO.Path]::GetTempPath()) "CRIVO-Metadata-$token.out";$stderr=Join-Path ([IO.Path]::GetTempPath()) "CRIVO-Metadata-$token.err"
    try{
        [IO.File]::WriteAllText($payloadPath,($payload|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false));Set-Status 'Atualizando os dados no Rekordbox…' 65
        $process=Start-Process -FilePath $helper -ArgumentList @("`"$payloadPath`"") -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr;Wait-CRIVOHelperProcess -Process $process -TimeoutSeconds 120
        $output=if(Test-Path -LiteralPath $stdout){[IO.File]::ReadAllText($stdout,[Text.Encoding]::UTF8).Trim()}else{''};$errorOutput=if(Test-Path -LiteralPath $stderr){[IO.File]::ReadAllText($stderr,[Text.Encoding]::UTF8).Trim()}else{''};$result=$null;if($output){try{$result=$output|ConvertFrom-Json}catch{}}
        $success=[bool]($result -and $result.PSObject.Properties['success'] -and [bool]$result.success);$exitCode=$null;try{if($null -ne $process.ExitCode){$exitCode=[int]$process.ExitCode}}catch{}
        if(($null -ne $exitCode -and $exitCode -ne 0) -or -not$success){$message=if($result -and $result.PSObject.Properties['message'] -and $result.message){[string]$result.message}elseif($errorOutput){$errorOutput}elseif($output){$output}else{'O helper não retornou um resultado válido.'};throw $message}
        $result|Add-Member NoteProperty BackupPath $backupDirectory -Force;return $result
    }catch{
        try{Restore-RekordboxDatabaseBackup -DatabaseDirectory $databaseDirectory -BackupDirectory $backupDirectory}catch{Write-AppLog -Message "Falha ao restaurar backup do Rekordbox: $($_.Exception.Message)" -Level ERROR}
        throw "A atualização falhou e o banco do Rekordbox foi restaurado.`n$($_.Exception.Message)`nBackup: $backupDirectory"
    }finally{foreach($temporary in @($payloadPath,$stdout,$stderr)){if(Test-Path -LiteralPath $temporary -PathType Leaf){[IO.File]::Delete($temporary)}}}
}

function Send-ODTToRekordbox {
    if(-not$script:Tracks.Count){Show-Message 'Analise uma pasta no CRIVO DJ antes de enviar uma playlist.' 'Enviar ao Rekordbox';return}
    $playlistName=if($OrganizerPlaylistNameText -and -not[string]::IsNullOrWhiteSpace($OrganizerPlaylistNameText.Text)){$OrganizerPlaylistNameText.Text.Trim()}else{'CRIVO DJ — Organizado'}
    $exportRoot=Join-Path (Get-AppDataRoot) 'Exports';[IO.Directory]::CreateDirectory($exportRoot)|Out-Null;$path=Join-Path $exportRoot 'CRIVO-DJ-Rekordbox.xml';$m3u8=Join-Path $exportRoot ((ConvertTo-SafePathPart $playlistName 'CRIVO DJ Organizado')+'.m3u8');$selected=@($script:Tracks|Where-Object{$_.Selected})
    try{
        Export-RekordboxXml -Tracks $selected -Path $path -PlaylistName $playlistName|Out-Null;Export-TracksM3U8 -Tracks $selected -Path $m3u8|Out-Null
        $import=Write-RekordboxPlaylistDirect -Tracks $selected -PlaylistName $playlistName
        Open-RekordboxApplication|Out-Null
        Show-Message "Playlist '$playlistName' gravada e verificada diretamente no banco do Rekordbox.`n`nTracks na playlist: $($import.tracksInPlaylist)`nAdicionadas à coleção: $($import.tracksAddedToCollection)`nAdicionadas à playlist: $($import.tracksAddedToPlaylist)`nJá analisadas: $($import.analyzedTracks)`nPrecisam analisar no Rekordbox: $($import.tracksNeedingAnalysis)`nBackup: $($import.BackupPath)" 'Playlist gravada no Rekordbox'
    }catch{Show-Message $_.Exception.Message 'Falha na gravação direta do Rekordbox' Error}
}

function Export-OrganizedPlanToRekordbox {
    param([Parameter(Mandatory)]$Plan,[Parameter(Mandatory)]$Operation)
    $playlistName=if(-not[string]::IsNullOrWhiteSpace($OrganizerPlaylistNameText.Text)){$OrganizerPlaylistNameText.Text.Trim()}else{'CRIVO DJ — Organizado'};$tracks=New-Object Collections.Generic.List[object]
    foreach($done in @($Operation.Items|Where-Object{$_.Result -in @('Copied','Moved','DuplicateSkipped') -and (Test-Path -LiteralPath $_.Destination -PathType Leaf)})){$item=@($Plan.Items|Where-Object Index -eq $done.Index|Select-Object -First 1);if($item.Count){$copy=$item[0].Track.PSObject.Copy();$copy|Add-Member NoteProperty FullName ([string]$done.Destination) -Force;$tracks.Add($copy)}}
    if(-not$tracks.Count){return $null};$exportRoot=Join-Path (Get-AppDataRoot) 'Exports';[IO.Directory]::CreateDirectory($exportRoot)|Out-Null;$path=Join-Path $exportRoot 'CRIVO-DJ-Rekordbox.xml';$m3u8=Join-Path $exportRoot ((ConvertTo-SafePathPart $playlistName 'CRIVO DJ Organizado')+'.m3u8');Export-RekordboxXml -Tracks $tracks.ToArray() -Path $path -PlaylistName $playlistName|Out-Null;Export-TracksM3U8 -Tracks $tracks.ToArray() -Path $m3u8|Out-Null;$import=Write-RekordboxPlaylistDirect -Tracks $tracks.ToArray() -PlaylistName $playlistName;Open-RekordboxApplication|Out-Null;return [pscustomobject]@{Path=$path;PlaylistFile=$m3u8;PlaylistName=$playlistName;Count=$tracks.Count;Import=$import}
}

function Select-RekordboxIntegrationXml {
    $dialog=New-Object Windows.Forms.OpenFileDialog;$dialog.Title='Selecionar master.db do Rekordbox';$dialog.Filter='Banco do Rekordbox (master.db)|master.db|Banco de dados (*.db)|*.db|Todos os arquivos (*.*)|*.*'
    if($dialog.ShowDialog() -ne [Windows.Forms.DialogResult]::OK){return};$script:RekordboxLibraryAudit=$null;Clear-AuditDisplay;$RekordboxXmlText.Text=$dialog.FileName
    if(-not$script:Settings.PSObject.Properties['Rekordbox']){$script:Settings|Add-Member NoteProperty Rekordbox ([pscustomobject]@{})};if(-not$script:Settings.Rekordbox.PSObject.Properties['DatabasePath']){$script:Settings.Rekordbox|Add-Member NoteProperty DatabasePath $dialog.FileName}else{$script:Settings.Rekordbox.DatabasePath=$dialog.FileName};Save-Settings
    $RekordboxSummaryText.Text='Base escolhida. Clique em Escanear biblioteca para iniciar a verificação somente leitura.'
}

function Clear-AuditDisplay {
    $script:RekordboxAudit=$null;$RekordboxAuditGrid.ItemsSource=@();$AuditCollectionCount.Text='—';$AuditMissingCount.Text='—';$AuditQualityCount.Text='—';$AuditDataCount.Text='—';$AuditDuplicateCount.Text='—';$ExportRekordboxAuditButton.IsEnabled=$false;$EditAuditMetadataButton.IsEnabled=$false;$ReviewAuditButton.IsEnabled=$false
}

function Reset-RekordboxAuditState {
    $script:RekordboxLibrary=$null;$script:RekordboxLibraryAudit=$null;$script:RekordboxUsbAudit=$null;Clear-AuditDisplay
}

function Show-AuditResult {
    param([Parameter(Mandatory)]$Audit)
    $script:RekordboxAudit=$Audit;$AuditCollectionCount.Text=[string]$Audit.Total;$AuditMissingCount.Text=[string]$Audit.MissingFiles;$AuditQualityCount.Text=[string]$Audit.QualityIssues;$AuditDataCount.Text=[string]$Audit.DataProblems
    $exact=if($Audit.PSObject.Properties['DuplicatePaths']){[int]$Audit.DuplicatePaths}else{0};$possible=if($Audit.PSObject.Properties['PossibleDuplicates']){[int]$Audit.PossibleDuplicates}else{0};$locations=if($Audit.PSObject.Properties['LocationIssues']){[int]$Audit.LocationIssues}else{0};$sourceFolders=if($Audit.PSObject.Properties['SourceFolders']){[int]$Audit.SourceFolders}else{0};$AuditDuplicateCount.Text="$exact / $possible"
    if([string]$Audit.Mode -eq 'Usb'){
        $AuditTotalLabel.Text='TRACKS NO DISPOSITIVO';$AuditMissingLabel.Text='ARQUIVOS COM FALHA';$AuditQualityLabel.Text='QUALIDADE SUSPEITA';$AuditDataLabel.Text='DADOS / ESTRUTURA';$AuditDuplicateLabel.Text='DUPLICATAS / POSSÍVEIS';$AuditReadOnlyText.Text='O dispositivo foi apenas lido. Nenhum arquivo ou banco foi alterado.'
        $RekordboxSummaryText.Text="$($Audit.Total) tracks | $exact duplicada(s), $possible possível(is) | $locations origem(ns) dispersa(s) em $sourceFolders pasta(s) | $($Audit.AnalysisFileCount) arquivo(s) de análise"
    }else{
        $AuditTotalLabel.Text='TRACKS NA COLEÇÃO';$AuditMissingLabel.Text='SEM ARQUIVO FÍSICO';$AuditQualityLabel.Text='QUALIDADE SUSPEITA';$AuditDataLabel.Text='DADOS / ANÁLISE FALTANTES';$AuditDuplicateLabel.Text='DUPLICATAS / POSSÍVEIS';$AuditReadOnlyText.Text='A verificação é somente leitura. Nenhuma alteração é aplicada automaticamente.'
        $unavailable=if($Audit.PSObject.Properties['UnavailableFiles']){[int]$Audit.UnavailableFiles}else{0};$availability=if($unavailable){" | $unavailable não verificada(s): unidade indisponível"}else{''}
        $RekordboxSummaryText.Text="$($Audit.Total) tracks e $($Audit.Playlists) playlists | $exact duplicada(s), $possible possível(is) | $locations origem(ns) dispersa(s) em $sourceFolders pasta(s)$availability"
    }
    $ExportRekordboxAuditButton.IsEnabled=$true;Update-RekordboxAuditView;Update-ContextInformation
}

function Set-AuditMode {
    param([ValidateSet('Library','Usb')][string]$Mode)
    $script:AuditMode=$Mode;$library=($Mode -eq 'Library')
    $AuditLibrarySourcePanel.Visibility=if($library){'Visible'}else{'Collapsed'};$AuditUsbSourcePanel.Visibility=if($library){'Collapsed'}else{'Visible'}
    $AuditLibraryModeButton.ClearValue([Windows.FrameworkElement]::StyleProperty);$AuditUsbModeButton.ClearValue([Windows.FrameworkElement]::StyleProperty)
    if($library){$AuditLibraryModeButton.Style=$window.FindResource('PrimaryButton');if($script:RekordboxLibraryAudit){Show-AuditResult $script:RekordboxLibraryAudit}else{Clear-AuditDisplay;$RekordboxSummaryText.Text='Escolha a base e clique em Escanear biblioteca.'}}
    else{$AuditUsbModeButton.Style=$window.FindResource('PrimaryButton');if($script:RekordboxUsbAudit){Show-AuditResult $script:RekordboxUsbAudit}else{Clear-AuditDisplay;$RekordboxSummaryText.Text='Escolha o pendrive exportado pelo Rekordbox e verifique sua integridade.'}}
}

function Select-RekordboxAuditUsb {
    $initial='';try{$drive=@(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=2' -ErrorAction Stop|Select-Object -First 1);if($drive.Count){$initial=[string]$drive[0].DeviceID+'\'}}catch{}
    $selected=Select-Folder 'Escolha a raiz do pendrive ou dispositivo exportado pelo Rekordbox' $initial;if(-not$selected){return};$AuditUsbPathText.Text=$selected;$script:RekordboxUsbAudit=$null;Clear-AuditDisplay;$RekordboxSummaryText.Text='Dispositivo escolhido. Clique em Verificar pendrive.'
}

function Update-RekordboxAuditView {
    if(-not$script:RekordboxAudit){return};$filter=[string](Get-SelectedTag $AuditFilterCombo);$search=$AuditSearchText.Text.Trim();$rows=@($script:RekordboxAudit.Rows)
    if($filter -eq 'Problems'){$rows=@($rows|Where-Object{$_.IssueCount -gt 0})}elseif($filter -eq 'Missing'){$rows=@($rows|Where-Object{$_.IssueCategories -match '(^|;)Missing(;|$)'})}elseif($filter -eq 'Unavailable'){$rows=@($rows|Where-Object{$_.IssueCategories -match '(^|;)Unavailable(;|$)'})}elseif($filter -eq 'Quality'){$rows=@($rows|Where-Object{$_.IssueCategories -match '(^|;)Quality(;|$)'})}elseif($filter -eq 'Metadata'){$rows=@($rows|Where-Object{$_.IssueCategories -match '(^|;)Metadata(;|$)'})}elseif($filter -eq 'Analysis'){$rows=@($rows|Where-Object{$_.IssueCategories -match '(^|;)Analysis(;|$)'})}elseif($filter -eq 'Duplicates'){$rows=@($rows|Where-Object{$_.IssueCategories -match '(^|;)(Duplicate|PossibleDuplicate)(;|$)'})}elseif($filter -eq 'Location'){$rows=@($rows|Where-Object{$_.IssueCategories -match '(^|;)Location(;|$)'})}elseif($filter -eq 'Structure'){$rows=@($rows|Where-Object{$_.IssueCategories -match '(^|;)Structure(;|$)'})}
    if($search){$rows=@($rows|Where-Object{([string]$_.Title).IndexOf($search,[StringComparison]::OrdinalIgnoreCase) -ge 0})};$RekordboxAuditGrid.ItemsSource=$rows;$EditAuditMetadataButton.IsEnabled=$false;$ReviewAuditButton.IsEnabled=$false
}

function Invoke-RekordboxIntegrationAudit {
    $path=[string]$RekordboxXmlText.Text;if(-not(Test-Path -LiteralPath $path -PathType Leaf)){Show-Message 'Escolha o arquivo master.db do Rekordbox.' 'Saúde do Rekordbox';return}
    try{
        Set-Status 'Pyrekordbox está lendo o master.db…' 10;Pump-Ui;$script:RekordboxLibrary=Get-RekordboxDatabaseLibrary -Path $path
        $progressAction=New-UiProgressAction -Message {param($current,$total,$name) "Verificando track $current de $total • $name"} -Percent {param($current,$total) 20+[int][Math]::Round(($current/[Math]::Max(1,$total))*75)}
        $script:RekordboxLibraryAudit=Get-RekordboxAudit -Library $script:RekordboxLibrary -Settings $script:Settings -OnProgress $progressAction;$script:RekordboxAudit=$script:RekordboxLibraryAudit
        Show-AuditResult $script:RekordboxLibraryAudit;Set-Status 'Auditoria da biblioteca concluída' 100
    }catch{$script:RekordboxLibraryAudit=$null;Clear-AuditDisplay;Write-AppLog -Message $_.Exception.ToString() -Level ERROR;Show-Message $_.Exception.Message 'Falha ao ler o banco do Rekordbox' Error}
}

function Invoke-RekordboxUsbIntegrityAudit {
    $path=[string]$AuditUsbPathText.Text;if(-not(Test-Path -LiteralPath $path -PathType Container)){Show-Message 'Escolha a raiz do pendrive ou dispositivo exportado pelo Rekordbox.' 'Integridade do pendrive';return}
    try{
        Set-Status 'Lendo a estrutura do dispositivo…' 5;Pump-Ui
        $progressAction=New-UiProgressAction -Message {param($current,$total,$name) "Verificando arquivo $current de $total • $name"} -Percent {param($current,$total) 10+[int][Math]::Round(($current/[Math]::Max(1,$total))*80)}
        $script:RekordboxUsbAudit=Get-RekordboxUsbAudit -Root $path -Settings $script:Settings -OnProgress $progressAction;Show-AuditResult $script:RekordboxUsbAudit;Set-Status 'Integridade do pendrive verificada' 100
    }catch{$script:RekordboxUsbAudit=$null;Clear-AuditDisplay;Write-AppLog -Message $_.Exception.ToString() -Level ERROR;Show-Message $_.Exception.Message 'Falha ao verificar o pendrive' Error}
}

function Update-AuditSelectionButtons {
    $selected=@($RekordboxAuditGrid.SelectedItems);$ReviewAuditButton.IsEnabled=($selected.Count -gt 0);$EditAuditMetadataButton.IsEnabled=$false
    if($selected.Count -ne 1){return};$row=$selected[0];$path=[string]$row.Location
    if(-not$path -or -not(Test-Path -LiteralPath $path -PathType Leaf)){return}
    $extension=[IO.Path]::GetExtension($path).ToLowerInvariant();$EditAuditMetadataButton.IsEnabled=(@($script:Settings.AudioExtensions|ForEach-Object{$_.ToLowerInvariant()}) -contains $extension)
}

function Show-AuditMetadataEditor {
    param([Parameter(Mandatory)]$Row,[string]$CapturePath)
    [xml]$editorXaml=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Width="760" Height="585" WindowStartupLocation="CenterOwner" WindowStyle="None" ResizeMode="NoResize" ShowInTaskbar="False" Background="#171613" FontFamily="Segoe UI" Foreground="#171613">
  <Window.Resources>
    <Style TargetType="TextBlock" />
    <Style TargetType="TextBox">
      <Setter Property="Height" Value="34"/><Setter Property="Padding" Value="9,6"/><Setter Property="FontSize" Value="13"/><Setter Property="Background" Value="#F3F1EC"/><Setter Property="Foreground" Value="#171613"/><Setter Property="BorderBrush" Value="#8B877F"/><Setter Property="BorderThickness" Value="1"/>
    </Style>
    <Style x:Key="FieldLabel" TargetType="TextBlock"><Setter Property="FontSize" Value="10"/><Setter Property="FontWeight" Value="Bold"/><Setter Property="Margin" Value="0,0,0,5"/></Style>
    <Style TargetType="Button">
      <Setter Property="Height" Value="36"/><Setter Property="Padding" Value="18,5"/><Setter Property="FontSize" Value="11"/><Setter Property="FontWeight" Value="SemiBold"/><Setter Property="BorderThickness" Value="1"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="Body" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Body" Property="Opacity" Value="0.86"/></Trigger><Trigger Property="IsPressed" Value="True"><Setter TargetName="Body" Property="Opacity" Value="0.70"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter TargetName="Body" Property="Opacity" Value="0.38"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
    </Style>
  </Window.Resources>
  <Border BorderBrush="#171613" BorderThickness="1" Background="#D5D1C8">
    <Grid>
      <Grid.RowDefinitions><RowDefinition Height="44"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
      <Grid x:Name="Header" Background="#171613">
        <TextBlock Text="ADICIONAR OU CORRIGIR METADADOS" Foreground="#F2F0EA" FontWeight="Bold" FontSize="12" VerticalAlignment="Center" Margin="16,0,50,0"/>
        <Button x:Name="CloseButton" Content="×" Width="44" Height="43" Padding="0" HorizontalAlignment="Right" Background="#171613" Foreground="#F2F0EA" BorderThickness="0" FontSize="18"/>
      </Grid>
      <Border Grid.Row="1" Background="#E4E1D9" Padding="20,16,20,14">
        <StackPanel>
          <TextBlock Text="REVISE OS DADOS DA TRACK" FontSize="15" FontWeight="Bold"/>
          <TextBlock Text="Preencha somente o que deseja salvar. O arquivo será atualizado com histórico de restauração; na auditoria da biblioteca, o Rekordbox também recebe a correção com backup." TextWrapping="Wrap" Foreground="#625E57" FontSize="11" Margin="0,5,0,0" LineHeight="17"/>
        </StackPanel>
      </Border>
      <Border Grid.Row="2" Margin="20,16,20,12" Padding="16" Background="#CBC7BE" BorderBrush="#969188" BorderThickness="1">
        <Grid>
          <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="14"/><ColumnDefinition/><ColumnDefinition Width="14"/><ColumnDefinition/></Grid.ColumnDefinitions>
          <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="14"/><RowDefinition Height="Auto"/><RowDefinition Height="14"/><RowDefinition Height="Auto"/><RowDefinition Height="14"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
          <StackPanel Grid.Row="0" Grid.ColumnSpan="5"><TextBlock Text="TÍTULO" Style="{StaticResource FieldLabel}"/><TextBox x:Name="TitleBox"/></StackPanel>
          <StackPanel Grid.Row="2" Grid.ColumnSpan="5"><TextBlock Text="ARTISTA" Style="{StaticResource FieldLabel}"/><TextBox x:Name="ArtistBox"/></StackPanel>
          <StackPanel Grid.Row="4" Grid.Column="0" Grid.ColumnSpan="3"><TextBlock Text="ÁLBUM" Style="{StaticResource FieldLabel}"/><TextBox x:Name="AlbumBox"/></StackPanel>
          <StackPanel Grid.Row="4" Grid.Column="4"><TextBlock Text="GÊNERO" Style="{StaticResource FieldLabel}"/><TextBox x:Name="GenreBox"/></StackPanel>
          <StackPanel Grid.Row="6" Grid.Column="0"><TextBlock Text="ANO" Style="{StaticResource FieldLabel}"/><TextBox x:Name="YearBox" MaxLength="4"/></StackPanel>
          <StackPanel Grid.Row="6" Grid.Column="2"><TextBlock Text="BPM" Style="{StaticResource FieldLabel}"/><TextBox x:Name="BpmBox"/></StackPanel>
          <StackPanel Grid.Row="6" Grid.Column="4"><TextBlock Text="TONALIDADE" Style="{StaticResource FieldLabel}"/><TextBox x:Name="KeyBox"/></StackPanel>
        </Grid>
      </Border>
      <Border Grid.Row="3" Margin="20,0,20,12" Padding="12,9" Background="#E4E1D9" BorderBrush="#AAA59B" BorderThickness="1">
        <StackPanel><TextBlock Text="ARQUIVO" FontSize="9" FontWeight="Bold"/><TextBlock x:Name="FilePathText" FontSize="10" Foreground="#625E57" Margin="0,3,0,0" TextTrimming="CharacterEllipsis" ToolTip="{Binding Text, RelativeSource={RelativeSource Self}}"/></StackPanel>
      </Border>
      <Grid Grid.Row="4" Margin="20,0,20,18">
        <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="8"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <TextBlock Text="Você poderá desfazer esta alteração pelo histórico." Foreground="#625E57" FontSize="10" VerticalAlignment="Center"/>
        <Button x:Name="CancelButton" Grid.Column="1" Content="CANCELAR" MinWidth="104" Background="#C5C1B8" Foreground="#171613" BorderBrush="#77726A" IsCancel="True"/>
        <Button x:Name="SaveButton" Grid.Column="3" Content="SALVAR METADADOS" MinWidth="156" Background="#171613" Foreground="#F2F0EA" BorderBrush="#171613" IsDefault="True"/>
      </Grid>
    </Grid>
  </Border>
</Window>
'@
    $reader=New-Object System.Xml.XmlNodeReader $editorXaml
    $dialog=[Windows.Markup.XamlReader]::Load($reader);if($window -and $window.IsLoaded){$dialog.Owner=$window};if($window.Icon){$dialog.Icon=$window.Icon}
    $boxes=@{};foreach($field in @('Title','Artist','Album','Genre','Year','Bpm','Key')){$boxes[$field]=$dialog.FindName("${field}Box");$value=if($Row.PSObject.Properties[$field]){[string]$Row.$field}else{''};if($field -eq 'Genre' -and $value -eq 'Gênero faltante'){$value=''};$boxes[$field].Text=$value}
    $dialog.FindName('FilePathText').Text=[string]$Row.Location
    $dialog.FindName('Header').Add_MouseLeftButtonDown({if($_.ClickCount -eq 1){try{$dialog.DragMove()}catch{}}})
    $dialog.FindName('CloseButton').Add_Click({$dialog.DialogResult=$false;$dialog.Close()})
    $dialog.FindName('CancelButton').Add_Click({$dialog.DialogResult=$false;$dialog.Close()})
    $dialog.FindName('SaveButton').Add_Click({$dialog.DialogResult=$true;$dialog.Close()})
    if($CapturePath){
        $dialog.Add_ContentRendered({
            $dialog.UpdateLayout();$visual=$dialog.Content
            $width=[Math]::Max(1,[int][Math]::Ceiling($visual.ActualWidth));$height=[Math]::Max(1,[int][Math]::Ceiling($visual.ActualHeight))
            $bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap($width,$height,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($visual)
            $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder;$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
            $stream=[IO.File]::Open($CapturePath,[IO.FileMode]::Create);try{$encoder.Save($stream)}finally{$stream.Dispose()}
            $dialog.DialogResult=$false;$dialog.Close()
        })
    }
    if(-not$dialog.ShowDialog()){return $null}
    $year=$boxes.Year.Text.Trim();if($year -and $year -notmatch '^\d{4}$'){Show-Message 'Informe o ano com quatro dígitos, por exemplo 2026.' 'Metadados inválidos' Warning;return $null}
    $bpmText=$boxes.Bpm.Text.Trim();$bpm=0.0;if($bpmText){if(-not[Double]::TryParse(($bpmText -replace ',','.'),[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$bpm) -or $bpm -lt 20 -or $bpm -gt 300){Show-Message 'Informe um BPM entre 20 e 300.' 'Metadados inválidos' Warning;return $null}}
    return [pscustomobject]@{Title=$boxes.Title.Text.Trim();Artist=$boxes.Artist.Text.Trim();Album=$boxes.Album.Text.Trim();Genre=$boxes.Genre.Text.Trim();Year=$year;Bpm=$(if($bpmText){$bpm}else{''});Key=$boxes.Key.Text.Trim()}
}

function Edit-SelectedAuditMetadata {
    $selected=@($RekordboxAuditGrid.SelectedItems);if($selected.Count -ne 1){Show-Message 'Selecione uma única track para editar os metadados.' 'Editar metadados';return};$row=$selected[0]
    $path=[string]$row.Location;if(-not(Test-Path -LiteralPath $path -PathType Leaf)){Show-Message 'O arquivo físico desta track não está disponível.' 'Editar metadados' Warning;return}
    $metadata=Show-AuditMetadataEditor -Row $row;if(-not$metadata){return};$tagTrack=[pscustomobject]@{FullName=$path;Title=$metadata.Title;Artist=$metadata.Artist;Album=$metadata.Album;Genre=$metadata.Genre;Year=$metadata.Year;Bpm=$metadata.Bpm;Key=$metadata.Key}
    $tagResult=$null;$databaseResult=$null
    try{
        Set-Status 'Salvando os metadados no arquivo…' 35;$tagResult=Write-ApprovedMetadata -Tracks @($tagTrack) -Template 'Edição manual da auditoria';if($tagResult.Errors){throw 'Não foi possível gravar os metadados no arquivo.'}
        if($script:AuditMode -eq 'Library' -and [string]$row.TrackID){$databaseResult=Write-RekordboxMetadataDirect -TrackID ([string]$row.TrackID) -Metadata $metadata}
        if($script:AuditMode -eq 'Library'){Invoke-RekordboxIntegrationAudit}else{Invoke-RekordboxUsbIntegrityAudit}
        $backupText=if($databaseResult){"`nBackup do Rekordbox: $($databaseResult.BackupPath)"}else{''};Show-Message "Metadados salvos e auditoria atualizada.$backupText" 'Metadados atualizados'
    }catch{
        if($tagResult -and $tagResult.Updated -and -not$databaseResult){try{Undo-Operation -Operation $tagResult.Operation|Out-Null}catch{Write-AppLog -Message "Falha ao restaurar tags: $($_.Exception.Message)" -Level ERROR}}
        Write-AppLog -Message $_.Exception.ToString() -Level ERROR;Show-Message $_.Exception.Message 'Falha ao salvar metadados' Error
    }
}

function Update-OrganizeMetadataButton {
    $selected=@($PreviewGrid.SelectedItems);$EditTrackMetadataButton.IsEnabled=$false
    if($selected.Count -ne 1){return};$path=[string]$selected[0].FullName
    if(-not$path -or -not(Test-Path -LiteralPath $path -PathType Leaf)){return};$extension=[IO.Path]::GetExtension($path).ToLowerInvariant();$EditTrackMetadataButton.IsEnabled=(@($script:Settings.AudioExtensions|ForEach-Object{$_.ToLowerInvariant()}) -contains $extension)
}

function Edit-SelectedOrganizeMetadata {
    $selected=@($PreviewGrid.SelectedItems);if($selected.Count -ne 1){Show-Message 'Selecione uma única track na lista para editar os metadados.' 'Editar metadados';return};$track=$selected[0];$path=[string]$track.FullName
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){Show-Message 'O arquivo físico desta track não está disponível.' 'Editar metadados' Warning;return}
    $metadata=Show-AuditMetadataEditor -Row ([pscustomobject]@{Title=[string]$track.Title;Artist=[string]$track.Artist;Album=[string]$track.Album;Genre=[string]$track.Genre;Year=[string]$track.Year;Bpm=[string]$track.Bpm;Key=[string]$track.Key;Location=$path});if(-not$metadata){return}
    $tagResult=$null;try{$tagResult=Write-ApprovedMetadata -Tracks @([pscustomobject]@{FullName=$path;Title=$metadata.Title;Artist=$metadata.Artist;Album=$metadata.Album;Genre=$metadata.Genre;Year=$metadata.Year;Bpm=$metadata.Bpm;Key=$metadata.Key}) -Template 'Edição manual da organização';if($tagResult.Errors){throw 'Não foi possível gravar os metadados no arquivo.'};foreach($field in @('Title','Artist','Album','Genre','Year','Bpm','Key')){if($metadata.$field){$track.$field=$metadata.$field}};if($track.Title){$track.MissingTitle=$false};if($metadata.Genre){$track.MissingGenre=$false};Update-TrackMetadataStatus -Track $track;$PreviewGrid.Items.Refresh();Update-Dashboard;Refresh-PreviewFilter;Invalidate-Plan;Show-Message 'Metadados salvos no arquivo e no histórico do CRIVO DJ.' 'Metadados atualizados'}catch{if($tagResult -and $tagResult.Updated){try{Undo-Operation -Operation $tagResult.Operation|Out-Null}catch{}};Write-AppLog -Message $_.Exception.ToString() -Level ERROR;Show-Message $_.Exception.Message 'Falha ao salvar metadados' Error}
}

function Show-AuditSelectionReview {
    $selected=@($RekordboxAuditGrid.SelectedItems);if(-not$selected.Count){Show-Message 'Selecione uma ou mais linhas da lista.' 'Revisar auditoria';return}
    $lines=New-Object Collections.Generic.List[string]
    foreach($row in @($selected|Select-Object -First 12)){
        $action=if($row.IssueCategories -match 'Unavailable'){'desbloquear ou reconectar a unidade e escanear novamente'}elseif($row.IssueCategories -match 'Missing'){'localizar novamente o arquivo no Rekordbox'}elseif($row.IssueCategories -match 'Integrity'){'substituir ou copiar novamente o arquivo'}elseif($row.IssueCategories -match 'Quality'){'comparar com uma fonte de melhor qualidade'}elseif($row.IssueCategories -match 'Metadata'){'revisar os campos de metadata'}elseif($row.IssueCategories -match 'Analysis'){'analisar novamente no Rekordbox e reexportar'}elseif($row.IssueCategories -match 'PossibleDuplicate'){'comparar versão, remix, duração e qualidade antes de decidir'}elseif($row.IssueCategories -match '(^|;)Duplicate(;|$)'){'comparar os caminhos e manter apenas a cópia correta'}elseif($row.IssueCategories -match 'Location'){'consolidar numa pasta gerenciada pelo CRIVO e depois relocalizar pelo Rekordbox'}elseif($row.IssueCategories -match 'Structure'){'reexportar ou reparar o dispositivo pelo Rekordbox'}else{'revisar manualmente'}
        $lines.Add("$($row.Title) — $action")
    }
    $extra=if($selected.Count -gt 12){"`n…e mais $($selected.Count-12) item(ns)."}else{''};Show-Message ("REVISÃO RECOMENDADA`n`n"+($lines -join "`n")+$extra+"`n`nNenhuma correção foi aplicada.") 'Revisar auditoria'
}

function Export-RekordboxIntegrationAuditFile {
    if(-not$script:RekordboxAudit){Show-Message 'Execute a auditoria primeiro.' 'Auditoria';return};$dialog=New-Object Windows.Forms.SaveFileDialog;$dialog.Title='Exportar auditoria';$dialog.Filter='CSV (*.csv)|*.csv|JSON (*.json)|*.json';$suffix=if([string]$script:RekordboxAudit.Mode -eq 'Usb'){'Pendrive'}else{'Rekordbox'};$dialog.FileName="CRIVO-DJ-Auditoria-$suffix.csv";if($dialog.ShowDialog() -ne [Windows.Forms.DialogResult]::OK){return};try{Export-RekordboxAudit -Audit $script:RekordboxAudit -Path $dialog.FileName|Out-Null;if(-not(Test-Path -LiteralPath $dialog.FileName -PathType Leaf) -or (Get-Item -LiteralPath $dialog.FileName).Length -le 0){throw 'O relatório não foi criado no destino escolhido.'};Show-Message "Auditoria exportada e conferida:`n$($dialog.FileName)" 'Auditoria'}catch{Write-AppLog -Message $_.Exception.ToString() -Level ERROR;Show-Message $_.Exception.Message 'Falha ao exportar auditoria' Error}
}

function Select-ToolkitUsbDevice {
    $initial=if(Test-Path -LiteralPath $ToolkitUsbPathText.Text -PathType Container){$ToolkitUsbPathText.Text}else{''}
    $selected=Select-Folder 'Escolha o pendrive ou uma pasta de teste' $initial
    if(-not$selected){return}
    $ToolkitUsbPathText.Text=$selected
    $script:UsbHealthReport=$null
    $script:UsbRecoveryPlan=$null
    $script:UsbCompatibilityReport=$null
    $script:UsbBackupPlan=$null
    $ToolkitChecksGrid.ItemsSource=@()
    $ToolkitProblemCount.Text='—';$ToolkitAttentionCount.Text='—';$ToolkitUnknownCount.Text='—'
    $ToolkitOverallText.Text='Pronto para verificar'
    $ToolkitExportButton.IsEnabled=$false
    $ToolkitFirstAidButton.IsEnabled=$false
    $ToolkitCompatibilityButton.IsEnabled=$false
    $ToolkitOpenEquipmentSourceButton.IsEnabled=$false
    $CompatibilityChecksGrid.ItemsSource=@()
    $ToolkitCompatibilityStatus.Text='Faça primeiro o diagnóstico do dispositivo'
    $ToolkitRecoveryStatusText.Text='Faça primeiro o diagnóstico do dispositivo'
    $ToolkitBackupSummaryText.Text='Escolha também onde a cópia será salva'
    $ToolkitCreateBackupButton.IsEnabled=$false
    Update-ContextInformation
}

function Invoke-ToolkitUsbHealth {
    $path=[string]$ToolkitUsbPathText.Text
    if(-not(Test-Path -LiteralPath $path -PathType Container)){
        Show-Message 'Escolha o pendrive ou uma pasta de teste antes de iniciar.' 'Kit de ferramentas USB'
        return
    }
    try {
        $ToolkitScanUsbButton.IsEnabled=$false
        Set-Status 'KIT DE FERRAMENTAS USB • VERIFICANDO EM MODO SOMENTE LEITURA' 0
        $progressAction=New-UiProgressAction -Message {param($current,$total,$name) "Verificando $current de $total • $name"} -Percent {param($current,$total) [int](($current/[Math]::Max(1,$total))*100)}
        $script:UsbHealthReport=Get-CrivoUsbHealth -Root $path -Settings $script:Settings -OnProgress $progressAction
        $ToolkitChecksGrid.ItemsSource=@($script:UsbHealthReport.Checks)
        $ToolkitProblemCount.Text=[string]$script:UsbHealthReport.ProblemCount
        $ToolkitAttentionCount.Text=[string]$script:UsbHealthReport.AttentionCount
        $ToolkitUnknownCount.Text=[string]$script:UsbHealthReport.UnknownCount
        $ToolkitOverallText.Text=[string]$script:UsbHealthReport.Overall
        $ToolkitLimitText.Text=[string]$script:UsbHealthReport.Limitations[0]
        $ToolkitExportButton.IsEnabled=$true
        $ToolkitCompatibilityButton.IsEnabled=($EquipmentProfileCombo.SelectedItem -ne $null)
        $legacyDatabase=Join-Path $path 'PIONEER\rekordbox\EXPORT.PDB'
        $recoveryHelper=Join-Path $PSScriptRoot 'Tools\CRIVO-UsbRecovery\CRIVO-UsbRecovery.exe'
        $ToolkitFirstAidButton.IsEnabled=(Test-Path -LiteralPath $legacyDatabase -PathType Leaf) -and (Test-Path -LiteralPath $recoveryHelper -PathType Leaf)
        $ToolkitRecoveryStatusText.Text=if($ToolkitFirstAidButton.IsEnabled){'Há informações do Rekordbox que podem ser revisadas para recuperação.'}else{'Nenhuma biblioteca antiga recuperável foi confirmada neste dispositivo.'}
        if(Test-Path -LiteralPath $ToolkitBackupDestinationText.Text -PathType Container){Update-ToolkitBackupPlan}
        Update-ContextInformation
    } catch {
        $script:UsbHealthReport=$null
        $script:UsbRecoveryPlan=$null
        $ToolkitChecksGrid.ItemsSource=@()
        $ToolkitFirstAidButton.IsEnabled=$false
        $ToolkitCompatibilityButton.IsEnabled=$false
        $ToolkitCreateBackupButton.IsEnabled=$false
        Write-AppLog -Message $_.Exception.ToString() -Level ERROR
        Show-Message $_.Exception.Message 'Falha no diagnóstico do dispositivo' Error
    } finally {
        $ToolkitScanUsbButton.IsEnabled=$true
    }
}

function Format-CrivoByteSize {
    param([int64]$Bytes)
    if($Bytes -ge 1TB){return ('{0:N2} TB' -f ($Bytes/1TB))}
    if($Bytes -ge 1GB){return ('{0:N2} GB' -f ($Bytes/1GB))}
    if($Bytes -ge 1MB){return ('{0:N1} MB' -f ($Bytes/1MB))}
    if($Bytes -ge 1KB){return ('{0:N1} KB' -f ($Bytes/1KB))}
    return "$Bytes bytes"
}

function Initialize-ToolkitEquipmentProfiles {
    try{
        $script:EquipmentCatalog=Get-CrivoEquipmentCatalog
        $EquipmentProfileCombo.ItemsSource=@($script:EquipmentCatalog.Profiles)
        if($EquipmentProfileCombo.Items.Count){$EquipmentProfileCombo.SelectedIndex=0}
    }catch{
        Write-AppLog -Message $_.Exception.ToString() -Level ERROR
        $EquipmentProfileCombo.ItemsSource=@();$ToolkitCompatibilityButton.IsEnabled=$false
        $ToolkitCompatibilityStatus.Text='O catálogo de equipamentos não pôde ser carregado'
    }
}

function Invoke-ToolkitCompatibility {
    if(-not$script:UsbHealthReport){Show-Message 'Execute primeiro o diagnóstico do dispositivo.' 'Compatibilidade';return}
    if(-not$EquipmentProfileCombo.SelectedItem){Show-Message 'Escolha o modelo que será usado.' 'Compatibilidade';return}
    try{
        $ToolkitCompatibilityButton.IsEnabled=$false
        Set-Status 'KIT DE FERRAMENTAS USB • COMPARANDO COM A DOCUMENTAÇÃO DO EQUIPAMENTO' 20
        $profileId=[string]$EquipmentProfileCombo.SelectedItem.Id
        $script:UsbCompatibilityReport=Test-CrivoEquipmentCompatibility -HealthReport $script:UsbHealthReport -ProfileId $profileId
        $CompatibilityChecksGrid.ItemsSource=@($script:UsbCompatibilityReport.Checks)
        $ToolkitCompatibilityStatus.Text=[string]$script:UsbCompatibilityReport.Overall
        $profile=$script:UsbCompatibilityReport.Profile
        $CompatibilitySourceText.Text="Fonte oficial: $($profile.SourceTitle) • catálogo revisado em $($script:EquipmentCatalog.ReviewedAt). $($profile.Notes)"
        $ToolkitOpenEquipmentSourceButton.Tag=[string]$profile.SourceUrl
        $ToolkitOpenEquipmentSourceButton.IsEnabled=-not[string]::IsNullOrWhiteSpace([string]$profile.SourceUrl)
        Set-Status "KIT DE FERRAMENTAS USB • COMPATIBILIDADE: $($script:UsbCompatibilityReport.Overall.ToUpperInvariant())" 100
    }catch{
        Write-AppLog -Message $_.Exception.ToString() -Level ERROR
        Show-Message $_.Exception.Message 'Não foi possível verificar a compatibilidade' Error
    }finally{$ToolkitCompatibilityButton.IsEnabled=$true}
}

function Update-ToolkitBackupPlan {
    $source=[string]$ToolkitUsbPathText.Text;$destination=[string]$ToolkitBackupDestinationText.Text
    $script:UsbBackupPlan=$null;$ToolkitCreateBackupButton.IsEnabled=$false
    if(-not(Test-Path -LiteralPath $source -PathType Container) -or -not(Test-Path -LiteralPath $destination -PathType Container)){return}
    try{
        Set-Status 'KIT DE FERRAMENTAS USB • PREPARANDO O PLANO DA CÓPIA' 0
        $script:UsbBackupPlan=New-CrivoUsbBackupPlan -SourceRoot $source -DestinationRoot $destination
        $size=Format-CrivoByteSize -Bytes ([int64]$script:UsbBackupPlan.TotalBytes)
        if(-not$script:UsbBackupPlan.EnoughSpace){
            $available=Format-CrivoByteSize -Bytes ([int64]$script:UsbBackupPlan.AvailableBytes)
            $ToolkitBackupSummaryText.Text="$($script:UsbBackupPlan.FileCount) arquivo(s), $size. Espaço insuficiente: $available disponível(is)."
        }else{
            $spaceText=if($script:UsbBackupPlan.SpaceConfirmed){'O espaço disponível foi conferido.'}else{'O Windows não informou o espaço disponível; o CRIVO avisará se a cópia falhar.'}
            $ToolkitBackupSummaryText.Text="$($script:UsbBackupPlan.FileCount) arquivo(s), $size. $spaceText"
            $ToolkitCreateBackupButton.IsEnabled=$true
        }
        Set-Status 'KIT DE FERRAMENTAS USB • PLANO DA CÓPIA PRONTO PARA REVISÃO' 100
    }catch{
        $ToolkitBackupSummaryText.Text=$_.Exception.Message
        Write-AppLog -Message $_.Exception.ToString() -Level ERROR
    }
}

function Select-ToolkitBackupDestination {
    $initial=if(Test-Path -LiteralPath $ToolkitBackupDestinationText.Text -PathType Container){$ToolkitBackupDestinationText.Text}else{''}
    $selected=Select-Folder 'Escolha onde salvar a cópia segura' $initial
    if($selected){$ToolkitBackupDestinationText.Text=$selected;Update-ToolkitBackupPlan}
}

function Invoke-ToolkitSafeBackup {
    if(-not$script:UsbBackupPlan){Show-Message 'Escolha a origem e o destino antes de criar a cópia.' 'Cópia segura';return}
    $size=Format-CrivoByteSize -Bytes ([int64]$script:UsbBackupPlan.TotalBytes)
    $confirmed=Show-CrivoConfirm -Message "O CRIVO copiará $($script:UsbBackupPlan.FileCount) arquivo(s), totalizando $size, e comparará a assinatura digital de cada arquivo.`n`nIsso pode demorar. O dispositivo original será usado somente para leitura." -Title 'Criar cópia segura' -ConfirmText 'CRIAR CÓPIA SEGURA' -CancelText 'VOLTAR'
    if(-not$confirmed){return}
    try{
        $ToolkitCreateBackupButton.IsEnabled=$false;$ToolkitChooseBackupDestinationButton.IsEnabled=$false;$ToolkitChooseUsbButton.IsEnabled=$false
        $progressAction=New-UiProgressAction -Message {param($current,$total,$name);$short=if($name.Length -gt 55){'…'+$name.Substring($name.Length-54)}else{$name};"Cópia segura: $current de $total • $short"} -Percent {param($current,$total) [int](($current/[Math]::Max(1,$total))*100)}
        $result=Invoke-CrivoUsbBackup -Plan $script:UsbBackupPlan -OnProgress $progressAction
        $ToolkitBackupResultText.Text="Cópia validada: $($result.FileCount) arquivo(s), $($result.VerifiedCount) assinatura(s) conferida(s)."
        Set-Status 'KIT DE FERRAMENTAS USB • CÓPIA SEGURA VALIDADA' 100
        $open=Show-CrivoDialog -Message "A cópia foi criada e validada.`n`n$($result.FileCount) arquivo(s)`n$size`n$($result.VerifiedCount) assinatura(s) digitais conferida(s)`n`nO dispositivo original não foi alterado." -Title 'Cópia segura concluída' -PrimaryText 'ABRIR CÓPIA' -SecondaryText 'FECHAR' -Question
        if($open){try{Start-Process -FilePath ([string]$result.BackupRoot)|Out-Null}catch{}}
    }catch{
        Write-AppLog -Message $_.Exception.ToString() -Level ERROR
        $ToolkitBackupResultText.Text='A cópia não foi concluída nem validada. A origem não foi alterada.'
        Show-Message $_.Exception.Message 'Cópia segura não concluída' Error
    }finally{
        $ToolkitChooseBackupDestinationButton.IsEnabled=$true;$ToolkitChooseUsbButton.IsEnabled=$true
        $ToolkitCreateBackupButton.IsEnabled=($null -ne $script:UsbBackupPlan -and [bool]$script:UsbBackupPlan.EnoughSpace)
    }
}

function Show-CrivoRecoveryCompletion {
    param([Parameter(Mandatory)]$Result)
    $message=@"
A cópia recuperada foi criada e validada.

$($Result.copied_file_count) arquivo(s) preservado(s)
$($Result.copied_audio_count) arquivo(s) de áudio
$($Result.created_playlist_count) playlist(s) criada(s)
$($Result.confirmed_link_count) posição(ões) de tracks recuperada(s)
$($Result.unresolved_link_count) posição(ões) não confirmada(s)

O dispositivo original não foi alterado.
"@
    $message=$message.Trim()+"`n`nPróximo passo: no Rekordbox, use Arquivo > Importar > Importar playlist e escolha os arquivos M3U8 da pasta Playlists. Depois, analise as tracks e exporte para outro pendrive."
    $openPlaylists=Show-CrivoDialog -Message $message -Title 'Cópia recuperada concluída' -PrimaryText 'ABRIR PLAYLISTS' -SecondaryText 'VER RELATÓRIO' -Question
    if($openPlaylists){
        $playlists=Join-Path ([string]$Result.recovery_root) 'Playlists'
        try{Start-Process -FilePath $playlists|Out-Null}catch{}
    }else{
        $report=Join-Path ([string]$Result.recovery_root) 'Relatorio-da-recuperacao.html'
        if(Test-Path -LiteralPath $report -PathType Leaf){try{Start-Process -FilePath $report|Out-Null}catch{}}
    }
}

function Show-ToolkitRecoveryReview {
    param([AllowNull()][object]$DemoPlan,[string]$CapturePath='')
    $source=[string]$ToolkitUsbPathText.Text
    if($DemoPlan){
        $plan=$DemoPlan
    }else{
        if(-not$script:UsbHealthReport){Show-Message 'Verifique o dispositivo antes de revisar a recuperação.' 'Recuperação';return}
        $database=Join-Path $source 'PIONEER\rekordbox\EXPORT.PDB'
        if(-not(Test-Path -LiteralPath $database -PathType Leaf)){
            Show-Message 'A biblioteca antiga do Rekordbox não foi encontrada neste dispositivo. Nenhuma recuperação foi iniciada.' 'Recuperação não disponível'
            return
        }
        try{
            $ToolkitFirstAidButton.IsEnabled=$false
            Set-Status 'KIT DE FERRAMENTAS USB • LENDO O QUE AINDA PODE SER RECUPERADO' 0
            $workingDirectory=Join-Path (Get-AppDataRoot) 'Planos de recuperacao'
            $script:UsbRecoveryPlan=New-CrivoUsbRecoveryPlan -SourceRoot $source -WorkingDirectory $workingDirectory -OnWait {Pump-Ui}
        }catch{
            Write-AppLog -Message $_.Exception.ToString() -Level ERROR
            Show-Message ($_.Exception.Message+"`n`nNenhum arquivo foi criado e o dispositivo original não foi alterado.") 'Não foi possível revisar a recuperação' Error
            return
        }finally{
            $ToolkitFirstAidButton.IsEnabled=$true
        }
        $plan=$script:UsbRecoveryPlan.Plan
    }
    $rows=@($plan.playlists|ForEach-Object{[pscustomobject]@{Playlist=[string]$_.path;Resultado=([string]$_.status).ToUpperInvariant();Confirmadas=[int]$_.resolved_entries;NaoConfirmadas=[int]$_.unresolved_entries}})
    $dialog=New-Object Windows.Window
    $dialog.Title='CRIVO DJ — Revisar recuperação';$dialog.Width=940;$dialog.Height=730;$dialog.MinWidth=820;$dialog.MinHeight=650
    $dialog.WindowStartupLocation='CenterOwner';$dialog.ResizeMode='CanResizeWithGrip';$dialog.WindowStyle='None';$dialog.ShowInTaskbar=$false
    $dialog.Background=[Windows.Media.BrushConverter]::new().ConvertFromString('#B4B0A8');$dialog.Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString('#171613');$dialog.FontFamily='Segoe UI'
    if($window -and $window.IsLoaded){$dialog.Owner=$window};if($window.Icon){$dialog.Icon=$window.Icon}
    $shell=New-Object Windows.Controls.Border;$shell.BorderBrush=[Windows.Media.BrushConverter]::new().ConvertFromString('#171613');$shell.BorderThickness='1'
    $layout=New-Object Windows.Controls.Grid;$layout.Background=[Windows.Media.BrushConverter]::new().ConvertFromString('#B4B0A8')
    foreach($height in @('Auto','Auto','Auto','*','Auto','Auto')){$definition=New-Object Windows.Controls.RowDefinition;$definition.Height=$height;$layout.RowDefinitions.Add($definition)}
    $header=New-Object Windows.Controls.Border;$header.Background=[Windows.Media.BrushConverter]::new().ConvertFromString('#171613');$header.Padding='18,13'
    $headerText=New-Object Windows.Controls.TextBlock;$headerText.Text='REVISAR RECUPERAÇÃO';$headerText.Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString('#F2F0EA');$headerText.FontWeight='Bold';$headerText.FontSize=14;$header.Child=$headerText;$header.Add_MouseLeftButtonDown({try{$dialog.DragMove()}catch{}});$layout.Children.Add($header)|Out-Null
    $intro=New-Object Windows.Controls.TextBlock;$intro.Text='O CRIVO leu a biblioteca em modo somente leitura. Revise abaixo o que foi possível confirmar antes de criar uma cópia em outro local.';$intro.TextWrapping='Wrap';$intro.Margin='18,15,18,8';$intro.FontSize=12;[Windows.Controls.Grid]::SetRow($intro,1);$layout.Children.Add($intro)|Out-Null
    $summary=New-Object Windows.Controls.Border;$summary.Background=[Windows.Media.BrushConverter]::new().ConvertFromString('#CAC6BD');$summary.BorderBrush=[Windows.Media.BrushConverter]::new().ConvertFromString('#777269');$summary.BorderThickness='1';$summary.Margin='18,4,18,10';$summary.Padding='12,9'
    $summaryText=New-Object Windows.Controls.TextBlock;$summaryText.Text="$($plan.physical_audio_count) ÁUDIOS LOCALIZADOS   •   $($plan.playlists_recoverable) PLAYLIST(S) RECUPERÁVEL(IS)   •   $($plan.playlists_partial) PARCIAL(IS)   •   $($plan.playlists_unconfirmed) NÃO CONFIRMADA(S)";$summaryText.FontWeight='Bold';$summaryText.FontSize=11;$summaryText.TextWrapping='Wrap';$summary.Child=$summaryText;[Windows.Controls.Grid]::SetRow($summary,2);$layout.Children.Add($summary)|Out-Null
    $grid=New-Object Windows.Controls.DataGrid;$grid.Margin='18,0,18,10';$grid.AutoGenerateColumns=$false;$grid.IsReadOnly=$true;$grid.SelectionMode='Single';$grid.SelectionUnit='FullRow';$grid.Background=[Windows.Media.BrushConverter]::new().ConvertFromString('#E1DED6');$grid.BorderBrush=[Windows.Media.BrushConverter]::new().ConvertFromString('#777269');$grid.ItemsSource=$rows
    foreach($spec in @(@('PLAYLIST','Playlist','*'),@('RESULTADO','Resultado','205'),@('CONFIRMADAS','Confirmadas','105'),@('NÃO CONFIRMADAS','NaoConfirmadas','125'))){$column=New-Object Windows.Controls.DataGridTextColumn;$column.Header=$spec[0];$column.Binding=New-Object Windows.Data.Binding($spec[1]);$column.Width=$spec[2];$grid.Columns.Add($column)}
    [Windows.Controls.Grid]::SetRow($grid,3);$layout.Children.Add($grid)|Out-Null
    $options=New-Object Windows.Controls.StackPanel;$options.Margin='18,0,18,8'
    $warning=New-Object Windows.Controls.TextBlock;$warning.Text='A recuperação pode ficar incompleta. O CRIVO recupera somente as informações que consegue confirmar. Dados danificados podem resultar em tracks ausentes, playlists incompletas ou ordem diferente da original. O dispositivo original não será alterado.';$warning.TextWrapping='Wrap';$warning.FontWeight='SemiBold';$warning.Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString('#6F4700');$warning.Margin='0,0,0,10';$options.Children.Add($warning)|Out-Null
    $organizationHint=New-Object Windows.Controls.TextBlock;$organizationHint.Text='Cada playlist confirmada ganhará uma pasta própria dentro de “Playlists”, com seus áudios e um arquivo que preserva a ordem. Tracks presentes em mais de uma playlist serão copiadas para cada pasta e podem aumentar o espaço usado.';$organizationHint.TextWrapping='Wrap';$organizationHint.Margin='0,0,0,10';$organizationHint.FontSize=12;$options.Children.Add($organizationHint)|Out-Null
    $destinationRow=New-Object Windows.Controls.Grid;$destinationRow.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition));$buttonColumn=New-Object Windows.Controls.ColumnDefinition;$buttonColumn.Width='190';$destinationRow.ColumnDefinitions.Add($buttonColumn)
    $destinationText=New-Object Windows.Controls.TextBox;$destinationText.IsReadOnly=$true;$destinationText.Height=34;$destinationText.VerticalContentAlignment='Center';$destinationText.Text=$(if($DemoPlan){'C:\Music\CRIVO DJ\Cópia recuperada'}else{'Escolha onde salvar a cópia recuperada'});$destinationText.Padding='8,0';$destinationRow.Children.Add($destinationText)|Out-Null
    $choose=New-Object Windows.Controls.Button;$choose.Content='ESCOLHER ONDE SALVAR';$choose.Height=34;$choose.Margin='8,0,0,0';$choose.Add_Click({$selected=Select-Folder 'Escolha onde salvar a cópia recuperada' '';if($selected){$destinationText.Text=$selected}});[Windows.Controls.Grid]::SetColumn($choose,1);$destinationRow.Children.Add($choose)|Out-Null;$options.Children.Add($destinationRow)|Out-Null
    $recoveryProgressText=New-Object Windows.Controls.TextBlock;$recoveryProgressText.Text=$(if($DemoPlan){'Pronto para criar a cópia recuperada'}else{'Aguardando a escolha do destino'});$recoveryProgressText.Margin='0,10,0,4';$recoveryProgressText.FontSize=11;$recoveryProgressText.FontWeight='SemiBold';$options.Children.Add($recoveryProgressText)|Out-Null
    $recoveryProgress=New-Object Windows.Controls.ProgressBar;$recoveryProgress.Height=14;$recoveryProgress.Minimum=0;$recoveryProgress.Maximum=100;$recoveryProgress.Value=0;$recoveryProgress.Background=[Windows.Media.BrushConverter]::new().ConvertFromString('#D8D5CE');$recoveryProgress.Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString('#171613');$options.Children.Add($recoveryProgress)|Out-Null
    [Windows.Controls.Grid]::SetRow($options,4);$layout.Children.Add($options)|Out-Null
    $footer=New-Object Windows.Controls.StackPanel;$footer.Orientation='Horizontal';$footer.HorizontalAlignment='Right';$footer.Margin='18,2,18,15'
    $back=New-Object Windows.Controls.Button;$back.Content='VOLTAR';$back.MinWidth=115;$back.Height=38;$back.Margin='0,0,8,0';$back.Add_Click({$dialog.Close()});$footer.Children.Add($back)|Out-Null
    $create=New-Object Windows.Controls.Button;$create.Content='CRIAR CÓPIA RECUPERADA';$create.MinWidth=215;$create.Height=38;$create.Background=[Windows.Media.BrushConverter]::new().ConvertFromString('#171613');$create.Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString('#F2F0EA');$create.FontWeight='Bold'
    $create.Add_Click({
        $destination=[string]$destinationText.Text
        if(-not(Test-Path -LiteralPath $destination -PathType Container)){Show-Message 'Escolha uma pasta válida fora do dispositivo original.' 'Onde salvar';return}
        $sourceFull=[IO.Path]::GetFullPath($source).TrimEnd('\')+'\';$destinationFull=[IO.Path]::GetFullPath($destination).TrimEnd('\')+'\'
        if($destinationFull.StartsWith($sourceFull,[StringComparison]::OrdinalIgnoreCase)){Show-Message 'Escolha um destino fora do dispositivo original.' 'Destino inseguro';return}
        $confirmed=Show-CrivoConfirm -Message "A recuperação pode ficar incompleta. Tracks ausentes, playlists incompletas ou ordem diferente podem permanecer quando os dados de origem estão danificados.`n`nCada playlist confirmada terá uma pasta com cópias dos seus áudios. Tracks presentes em várias playlists ocuparão espaço em cada pasta.`n`nO CRIVO criará e validará uma nova cópia. O dispositivo original não será alterado." -Title 'Criar cópia recuperada' -ConfirmText 'CRIAR CÓPIA RECUPERADA' -CancelText 'VOLTAR E REVISAR'
        if(-not$confirmed){return}
        try{
            $create.IsEnabled=$false;$choose.IsEnabled=$false;$back.IsEnabled=$false
            $recoveryProgressText.Text='Criando a cópia e conferindo os arquivos…';$recoveryProgress.IsIndeterminate=$true;Pump-Ui
            Set-Status 'KIT DE FERRAMENTAS USB • CRIANDO E VALIDANDO A CÓPIA RECUPERADA' 10
            $result=Invoke-CrivoUsbRecoveryCopy -PlanPath $script:UsbRecoveryPlan.PlanPath -DestinationRoot $destination -OnWait {Pump-Ui}
            $recoveryProgress.IsIndeterminate=$false;$recoveryProgress.Value=100;$recoveryProgressText.Text='Cópia recuperada criada e conferida';Pump-Ui
            Set-Status 'KIT DE FERRAMENTAS USB • CÓPIA RECUPERADA VALIDADA' 100
            $dialog.Close();Show-CrivoRecoveryCompletion -Result $result
        }catch{
            Write-AppLog -Message $_.Exception.ToString() -Level ERROR
            $recoveryProgress.IsIndeterminate=$false;$recoveryProgress.Value=0;$recoveryProgressText.Text='A recuperação não foi concluída';Pump-Ui
            Show-Message ($_.Exception.Message+"`n`nA origem não foi alterada. Não use uma cópia que não tenha sido validada pelo CRIVO.") 'A cópia recuperada não foi concluída' Error
            $create.IsEnabled=$true;$choose.IsEnabled=$true;$back.IsEnabled=$true
        }
    });$footer.Children.Add($create)|Out-Null
    [Windows.Controls.Grid]::SetRow($footer,5);$layout.Children.Add($footer)|Out-Null
    $shell.Child=$layout;$dialog.Content=$shell
    if($CapturePath){
        $dialog.Add_ContentRendered({
            $dialog.UpdateLayout();$visual=$dialog.Content
            $width=[Math]::Max(1,[int][Math]::Ceiling($visual.ActualWidth));$height=[Math]::Max(1,[int][Math]::Ceiling($visual.ActualHeight))
            $bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap($width,$height,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($visual)
            $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder;$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
            $stream=[IO.File]::Open($CapturePath,[IO.FileMode]::Create);try{$encoder.Save($stream)}finally{$stream.Dispose()}
            $dialog.Close()
        })
    }
    [void]$dialog.ShowDialog()
}

function Export-ToolkitUsbHealth {
    if(-not$script:UsbHealthReport){Show-Message 'Execute o diagnóstico antes de exportar.' 'Kit de ferramentas USB';return}
    try{
        $reportDirectory=Join-Path (Get-AppDataRoot) 'Relatorios'
        $export=Export-CrivoUsbHealthReport -Report $script:UsbHealthReport -Directory $reportDirectory
        if(-not(Test-Path -LiteralPath $export.HtmlPath -PathType Leaf) -or -not(Test-Path -LiteralPath $export.TechnicalPath -PathType Leaf)){throw 'Os arquivos do diagnóstico não foram criados por completo.'}
        try{Start-Process -FilePath $export.HtmlPath|Out-Null}catch{}
        Show-Message "Relatório visual e arquivo técnico foram criados e conferidos.`n`n$reportDirectory" 'Diagnóstico exportado'
    }catch{Write-AppLog -Message $_.Exception.ToString() -Level ERROR;Show-Message $_.Exception.Message 'Falha ao exportar diagnóstico' Error}
}

function Open-RekordboxApplication {
    $configured='';if($script:Settings.PSObject.Properties['Rekordbox'] -and $script:Settings.Rekordbox.PSObject.Properties['ExecutablePath']){$configured=[Environment]::ExpandEnvironmentVariables([string]$script:Settings.Rekordbox.ExecutablePath)}
    $candidates=@($configured,"$env:ProgramFiles\rekordbox\rekordbox.exe","$env:ProgramFiles\Pioneer\rekordbox 7\rekordbox.exe","$env:ProgramFiles\AlphaTheta\rekordbox 7\rekordbox.exe","${env:ProgramFiles(x86)}\Pioneer\rekordbox\rekordbox.exe")
    $running=@(Get-Process -ErrorAction SilentlyContinue|Where-Object{$_.ProcessName -match '^rekordbox' -and $_.MainWindowHandle -ne 0}|Select-Object -First 1);if($running.Count){return $running[0]}
    $exe=@($candidates|Where-Object{$_ -and (Test-Path -LiteralPath $_ -PathType Leaf)}|Select-Object -First 1);if(-not$exe.Count){throw 'O executável do Rekordbox não foi localizado. Escolha o rekordbox.exe no menu Organizar.'}
    $process=Start-Process -FilePath $exe[0] -PassThru;$limit=[DateTime]::UtcNow.AddSeconds(60)
    do{Start-Sleep -Milliseconds 500;try{$process.Refresh()}catch{};if($process.HasExited){throw 'O Rekordbox foi encerrado antes de abrir a janela principal.'}}while($process.MainWindowHandle -eq 0 -and [DateTime]::UtcNow -lt $limit)
    if($process.MainWindowHandle -eq 0){throw 'O Rekordbox não apresentou a janela principal dentro de 60 segundos.'};return $process
}

function Get-RekordboxUiElements {
    param([Parameter(Mandatory)][int]$TargetProcessId)
    $condition=New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ProcessIdProperty,$TargetProcessId)
    return [Windows.Automation.AutomationElement]::RootElement.FindAll([Windows.Automation.TreeScope]::Descendants,$condition)
}

function ConvertTo-UiName {
    param([AllowNull()][string]$Name)
    if([string]::IsNullOrWhiteSpace($Name)){return ''};return (($Name -replace '[&_]','' -replace '\.{3}$','').Trim().ToLowerInvariant())
}

function Find-RekordboxUiElement {
    param([Parameter(Mandatory)][int]$TargetProcessId,[Parameter(Mandatory)][scriptblock]$Predicate)
    foreach($element in @(Get-RekordboxUiElements -TargetProcessId $TargetProcessId)){try{$name=ConvertTo-UiName ([string]$element.Current.Name);$type=$element.Current.ControlType;if(& $Predicate $name $type){return $element}}catch{}}
    return $null
}

function Invoke-UiElement {
    param([Parameter(Mandatory)]$Element,[switch]$Expand)
    $pattern=$null
    if($Expand -and $Element.TryGetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern,[ref]$pattern)){([Windows.Automation.ExpandCollapsePattern]$pattern).Expand();return}
    $pattern=$null;if($Element.TryGetCurrentPattern([Windows.Automation.InvokePattern]::Pattern,[ref]$pattern)){([Windows.Automation.InvokePattern]$pattern).Invoke();return}
    $pattern=$null;if($Element.TryGetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern,[ref]$pattern)){([Windows.Automation.SelectionItemPattern]$pattern).Select();return}
    throw "O controle '$($Element.Current.Name)' não permite acionamento automático."
}

function Find-RekordboxFileNameBox {
    param([Parameter(Mandatory)][int]$TargetProcessId)
    foreach($element in @(Get-RekordboxUiElements -TargetProcessId $TargetProcessId)){try{if($element.Current.ControlType -eq [Windows.Automation.ControlType]::Edit -and ([string]$element.Current.AutomationId -eq '1148' -or (ConvertTo-UiName ([string]$element.Current.Name)) -match 'file name|nome do arquivo|nome do ficheiro')){return $element}}catch{}}
    return $null
}

function Open-RekordboxImportDialogWithKeyboard {
    param([Parameter(Mandatory)]$Process)
    [void][OdtTaskbarIdentity]::ShowWindow([IntPtr]$Process.MainWindowHandle,9);[void][OdtTaskbarIdentity]::SetForegroundWindow([IntPtr]$Process.MainWindowHandle);Start-Sleep -Milliseconds 250
    # Rekordbox em inglês usa File > Import > Playlist; em português, Arquivo > Importar > Playlist/Lista.
    # As sequências abaixo usam apenas os aceleradores dos menus, sem mover o mouse.
    $sequences=@(@('%f','i','p'),@('%a','i','p'),@('%a','i','l'),@('%f','i','l'))
    foreach($sequence in $sequences){
        [Windows.Forms.SendKeys]::SendWait('{ESC}{ESC}')
        foreach($key in $sequence){[Windows.Forms.SendKeys]::SendWait($key);Start-Sleep -Milliseconds 220}
        $limit=[DateTime]::UtcNow.AddSeconds(3);do{$box=Find-RekordboxFileNameBox -TargetProcessId ([int]$Process.Id);if($box){return $box};Start-Sleep -Milliseconds 200}while([DateTime]::UtcNow -lt $limit)
    }
    [Windows.Forms.SendKeys]::SendWait('{ESC}{ESC}');return $null
}

function Import-RekordboxPlaylistAutomatically {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$PlaylistName)
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "Playlist M3U8 não encontrada: $Path"}
    try{
        Set-Status 'Abrindo o Rekordbox para importar a playlist…' 90;$process=Open-RekordboxApplication;$rekordboxProcessId=[int]$process.Id
        $limit=[DateTime]::UtcNow.AddSeconds(3);$fileMenu=$null
        do{$fileMenu=Find-RekordboxUiElement -TargetProcessId $rekordboxProcessId -Predicate {param($name,$type)$type -eq [Windows.Automation.ControlType]::MenuItem -and $name -in @('file','arquivo','ficheiro')};if(-not$fileMenu){Start-Sleep -Milliseconds 500}}while(-not$fileMenu -and [DateTime]::UtcNow -lt $limit)
        $fileNameBox=$null
        if($fileMenu){
            try{Invoke-UiElement -Element $fileMenu -Expand;Start-Sleep -Milliseconds 350;$importMenu=Find-RekordboxUiElement -TargetProcessId $rekordboxProcessId -Predicate {param($name,$type)$type -eq [Windows.Automation.ControlType]::MenuItem -and $name -in @('import','importar')};if($importMenu){Invoke-UiElement -Element $importMenu -Expand;Start-Sleep -Milliseconds 350;$playlistMenu=Find-RekordboxUiElement -TargetProcessId $rekordboxProcessId -Predicate {param($name,$type)$type -eq [Windows.Automation.ControlType]::MenuItem -and $name -match 'import' -and ($name -match 'playlist' -or $name -match 'lista')};if($playlistMenu){Invoke-UiElement -Element $playlistMenu}}}catch{}
            $dialogLimit=[DateTime]::UtcNow.AddSeconds(5);do{$fileNameBox=Find-RekordboxFileNameBox -TargetProcessId $rekordboxProcessId;if(-not$fileNameBox){Start-Sleep -Milliseconds 250}}while(-not$fileNameBox -and [DateTime]::UtcNow -lt $dialogLimit)
        }
        if(-not$fileNameBox){$fileNameBox=Open-RekordboxImportDialogWithKeyboard -Process $process}
        if(-not$fileNameBox){throw 'A janela de seleção do arquivo não apareceu.'}
        $valuePattern=$null;if(-not$fileNameBox.TryGetCurrentPattern([Windows.Automation.ValuePattern]::Pattern,[ref]$valuePattern)){throw 'O campo de nome do arquivo não aceita preenchimento automático.'};([Windows.Automation.ValuePattern]$valuePattern).SetValue($Path)
        $openButton=Find-RekordboxUiElement -TargetProcessId $rekordboxProcessId -Predicate {param($name,$type)$type -eq [Windows.Automation.ControlType]::Button -and $name -in @('open','abrir')}
        if(-not$openButton){throw 'O botão Abrir da janela de importação não foi localizado.'};Invoke-UiElement -Element $openButton

        Set-Status 'Confirmando a playlist no Rekordbox…' 96;$verified=$false;$verifyLimit=[DateTime]::UtcNow.AddSeconds(25);$wanted=ConvertTo-UiName $PlaylistName
        $playlistPredicate={param($name,$type)$name -eq $wanted}.GetNewClosure()
        do{$found=Find-RekordboxUiElement -TargetProcessId $rekordboxProcessId -Predicate $playlistPredicate;if($found){$verified=$true;break};Start-Sleep -Milliseconds 500}while([DateTime]::UtcNow -lt $verifyLimit)
        Set-Status $(if($verified){'Playlist importada e confirmada no Rekordbox'}else{'Playlist importada; confirmação visual indisponível'}) 100
        return [pscustomobject]@{Success=$true;Verified=$verified;Message=$(if($verified){'Playlist confirmada.'}else{'O diálogo aceitou o arquivo, mas o nome não ficou visível para a automação.'})}
    }catch{
        Write-AppLog -Message $_.Exception.ToString() -Level ERROR;Set-Status 'Importação automática não concluída' 100
        return [pscustomobject]@{Success=$false;Verified=$false;Message=$_.Exception.Message}
    }
}

function Select-RekordboxExecutable {
    $dialog=New-Object Windows.Forms.OpenFileDialog;$dialog.Title='Escolher o executável do Rekordbox';$dialog.Filter='Aplicativo Rekordbox (rekordbox.exe)|rekordbox.exe|Executáveis (*.exe)|*.exe'
    $current=[string]$RekordboxExeText.Text;if(Test-Path -LiteralPath $current -PathType Leaf){$dialog.InitialDirectory=Split-Path -Parent $current;$dialog.FileName=Split-Path -Leaf $current}
    if($dialog.ShowDialog() -ne [Windows.Forms.DialogResult]::OK){return}
    if(-not$script:Settings.PSObject.Properties['Rekordbox']){$script:Settings|Add-Member NoteProperty Rekordbox ([pscustomobject]@{})}
    if(-not$script:Settings.Rekordbox.PSObject.Properties['ExecutablePath']){$script:Settings.Rekordbox|Add-Member NoteProperty ExecutablePath $dialog.FileName}else{$script:Settings.Rekordbox.ExecutablePath=$dialog.FileName}
    Save-Settings;$RekordboxExeText.Text=$dialog.FileName
}

function Show-RulesDialog {
    $form = New-Object Windows.Forms.Form
    $form.Text='Regras, formatos e qualidade'; $form.Width=720; $form.Height=740; $form.AutoScroll=$true; $form.StartPosition='CenterParent'; $form.Font=New-Object Drawing.Font('Arial',9); $form.BackColor=[Drawing.Color]::FromArgb(195,195,195); $form.ForeColor=[Drawing.Color]::FromArgb(20,20,20)
    $labels = @('Extensões de áudio (separadas por vírgula)','Extensões ignoradas','Pastas ignoradas','Normalização de gêneros (origem=destino)','Faixas de BPM (mín-máx=nome)','Pastas favoritas','Prioridade sem gênero (Metadata, SourceFolder, MissingGenre)','Qualidade mínima: bitrate MP3, sample rate','Termos removidos do nome','Chave de cliente AcoustID (opcional)','Confiança mínima para pré-selecionar sugestões (0–100)')
    $values = @(
        (@($script:Settings.AudioExtensions) -join ', '), (@($script:Settings.ExcludedExtensions) -join ', '), (@($script:Settings.ExcludedFolders) -join ', '),
        (@($script:Settings.GenreAliases.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join "`r`n"),
        (@($script:Settings.BpmRanges | ForEach-Object { "$($_.Min)-$($_.Max)=$($_.Name)" }) -join "`r`n"), (@($script:Settings.Favorites) -join "`r`n"),
        (@($script:Settings.GenreFallbackPriority) -join ', '), ("$($script:Settings.Quality.MinimumMp3Bitrate), $($script:Settings.Quality.MinimumSampleRate)"), (@($script:Settings.NameRules.RemoveTerms) -join ', '),
        ([string]$script:Settings.InternetMetadata.AcoustIdClientKey), ([string]$script:Settings.InternetMetadata.MinimumConfidence)
    )
    $boxes=@(); $y=12
    for($i=0;$i -lt $labels.Count;$i++) {
        $label=New-Object Windows.Forms.Label; $label.Text=$labels[$i]; $label.Left=14; $label.Top=$y; $label.Width=660; $form.Controls.Add($label); $y+=21
        $box=New-Object Windows.Forms.TextBox; $box.Left=14; $box.Top=$y; $box.Width=670; $box.BackColor=[Drawing.Color]::FromArgb(232,232,232); $box.ForeColor=[Drawing.Color]::FromArgb(20,20,20); $box.Text=$values[$i]
        if($i -in @(3,4,5)){$box.Multiline=$true;$box.ScrollBars='Vertical';$box.Height=72;$y+=80}else{$box.Height=25;$y+=34}
        $form.Controls.Add($box); $boxes += $box
    }
    $simple=New-Object Windows.Forms.CheckBox; $simple.Text='Log técnico detalhado'; $simple.Left=14; $simple.Top=$y; $simple.Width=220; $simple.Checked=($script:Settings.LogLevel -eq 'Detailed'); $form.Controls.Add($simple)
    $writeDefault=New-Object Windows.Forms.CheckBox;$writeDefault.Text='Gravar tags aprovadas por padrão';$writeDefault.Left=230;$writeDefault.Top=$y;$writeDefault.Width=240;$writeDefault.Checked=[bool]$script:Settings.InternetMetadata.WriteApprovedTags;$form.Controls.Add($writeDefault)
    $ok=New-Object Windows.Forms.Button; $ok.Text='Salvar regras'; $ok.Left=474; $ok.Top=$y-3; $ok.Width=100; $ok.DialogResult='OK'; $form.Controls.Add($ok)
    $cancel=New-Object Windows.Forms.Button; $cancel.Text='Cancelar'; $cancel.Left=584; $cancel.Top=$y-3; $cancel.Width=100; $cancel.DialogResult='Cancel'; $form.Controls.Add($cancel); $form.AcceptButton=$ok; $form.CancelButton=$cancel
    Set-CrivoFormStyle -Form $form -Title 'Regras, formatos e qualidade'
    if($form.ShowDialog() -ne [Windows.Forms.DialogResult]::OK){return}
    try {
        $script:Settings.AudioExtensions=@($boxes[0].Text -split '[,;]' | ForEach-Object { $value=$_.Trim().ToLower();if($value -and -not$value.StartsWith('.')){'.'+$value}else{$value} } | Where-Object { $_ })
        $script:Settings.ExcludedExtensions=@($boxes[1].Text -split '[,;]' | ForEach-Object { $value=$_.Trim().ToLower();if($value -and -not$value.StartsWith('.')){'.'+$value}else{$value} } | Where-Object { $_ })
        $script:Settings.ExcludedFolders=@($boxes[2].Text -split '[,;]' | ForEach-Object Trim | Where-Object { $_ })
        $aliases=[ordered]@{}; foreach($line in $boxes[3].Lines){if($line -match '^\s*([^=]+)=(.+)$'){$aliases[$Matches[1].Trim().ToUpperInvariant()]=$Matches[2].Trim()}}
        $ranges=@(); foreach($line in $boxes[4].Lines){if($line -match '^\s*(\d+)\s*-\s*(\d+)\s*=(.+)$'){$ranges += [pscustomobject]@{Min=[int]$Matches[1];Max=[int]$Matches[2];Name=$Matches[3].Trim()}}}
        if($aliases.Count){$script:Settings.GenreAliases=[pscustomobject]$aliases}; if($ranges.Count){$script:Settings.BpmRanges=$ranges}
        $script:Settings.Favorites=@($boxes[5].Lines | ForEach-Object Trim | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) })
        $priority=@($boxes[6].Text -split '[,;]' | ForEach-Object Trim | Where-Object { $_ -in @('Metadata','SourceFolder','MissingGenre','_PENDENTE') }|ForEach-Object{if($_ -eq '_PENDENTE'){'MissingGenre'}else{$_}}); if($priority.Count){$script:Settings.GenreFallbackPriority=$priority}
        if($boxes[7].Text -match '^\s*(\d+)\s*[,;]\s*(\d+)\s*$'){$script:Settings.Quality.MinimumMp3Bitrate=[int]$Matches[1];$script:Settings.Quality.MinimumSampleRate=[int]$Matches[2]}
        $script:Settings.NameRules.RemoveTerms=@($boxes[8].Text -split '[,;]' | ForEach-Object Trim | Where-Object { $_ })
        $script:Settings.InternetMetadata.AcoustIdClientKey=$boxes[9].Text.Trim();if($boxes[10].Text -match '^\d{1,3}$'){$script:Settings.InternetMetadata.MinimumConfidence=[Math]::Min(100,[Math]::Max(0,[int]$boxes[10].Text))}
        $script:Settings.InternetMetadata.WriteApprovedTags=[bool]$writeDefault.Checked
        $script:Settings.LogLevel=$(if($simple.Checked){'Detailed'}else{'Simple'}); Save-Settings
        if(Test-Path -LiteralPath $SourceText.Text -PathType Container){[void](Scan-SelectedFolder);Invalidate-Plan}
    } catch { Show-Message $_.Exception.Message 'Regras inválidas' Error }
}

function Export-CurrentSimulation {
    if(-not $script:Plan){Show-Message 'Escolha origem e destino para calcular a simulação.';return}
    $dialog=New-Object Windows.Forms.SaveFileDialog; $dialog.Title='Exportar simulação (dry-run)'; $dialog.Filter='CSV (*.csv)|*.csv|JSON (*.json)|*.json'; $dialog.FileName="CRIVO-DJ-simulacao-$($script:Plan.Id).csv"
    if($dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK){try{Export-OrganizationPlan -Plan $script:Plan -Path $dialog.FileName | Out-Null;if(-not(Test-Path -LiteralPath $dialog.FileName -PathType Leaf) -or (Get-Item -LiteralPath $dialog.FileName).Length -le 0){throw 'A simulação não foi criada no destino escolhido.'};Show-Message "Simulação exportada e conferida sem mover ou copiar arquivos.`n`n$($dialog.FileName)"}catch{Write-AppLog -Message $_.Exception.ToString() -Level ERROR;Show-Message $_.Exception.Message 'Falha ao exportar simulação' Error}}
}

function Export-Configuration {
    $dialog=New-Object Windows.Forms.SaveFileDialog; $dialog.Filter='Configuração JSON (*.json)|*.json'; $dialog.FileName='CRIVO-DJ-config.json'
    if($dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK){try{Write-JsonFile -Path $dialog.FileName -Value $script:Settings;if(-not(Test-Path -LiteralPath $dialog.FileName -PathType Leaf) -or (Get-Item -LiteralPath $dialog.FileName).Length -le 0){throw 'O arquivo de configuração não foi criado.'};Show-Message "Configuração exportada e conferida:`n$($dialog.FileName)"}catch{Write-AppLog -Message $_.Exception.ToString() -Level ERROR;Show-Message $_.Exception.Message 'Falha ao exportar configuração' Error}}
}

function Import-Configuration {
    $dialog=New-Object Windows.Forms.OpenFileDialog; $dialog.Filter='Configuração JSON (*.json)|*.json'
    if($dialog.ShowDialog() -ne [Windows.Forms.DialogResult]::OK){return}; $candidate=Read-JsonFile -Path $dialog.FileName
    $required=@('AudioExtensions','ExcludedExtensions','ExcludedFolders','Favorites','DuplicateLevel','MissingMetadataPolicy','UnknownValues','GenreAliases','BpmRanges','Quality','NameRules','LogLevel','InternetMetadata','Acquisition')
    if(-not $candidate -or @($required | Where-Object { -not $candidate.PSObject.Properties[$_] }).Count){Show-Message 'O arquivo não contém uma configuração completa e válida.' 'Importação recusada' Error;return}
    $acquisitionRequired=@('DownloadPath','DownloaderPath','SpotifyResolverPath','FFmpegPath');if(-not$candidate.Acquisition -or @($acquisitionRequired|Where-Object{-not$candidate.Acquisition.PSObject.Properties[$_]}).Count){Show-Message 'A configuração de downloads está incompleta.' 'Importação recusada' Error;return}
    if(-not$candidate.PSObject.Properties['WatchFolderEnabled']){$candidate|Add-Member NoteProperty WatchFolderEnabled $false}
    if(-not$candidate.PSObject.Properties['Rekordbox'] -and $script:Settings.PSObject.Properties['Rekordbox']){$candidate|Add-Member NoteProperty Rekordbox $script:Settings.Rekordbox}
    $script:Settings=$candidate; Save-Settings; Select-ComboTag $DuplicateLevelCombo ([string]$script:Settings.DuplicateLevel); Select-ComboTag $MissingPolicyCombo ([string]$script:Settings.MissingMetadataPolicy);$WatchFolderCheck.IsChecked=[bool]$script:Settings.WatchFolderEnabled;$DownloadDestinationText.Text=Get-ODTDownloadPath
    $configuredRb='';if($script:Settings.PSObject.Properties['Rekordbox'] -and $script:Settings.Rekordbox.PSObject.Properties['ExecutablePath']){$configuredRb=[Environment]::ExpandEnvironmentVariables([string]$script:Settings.Rekordbox.ExecutablePath)};$RekordboxExeText.Text=if($configuredRb){$configuredRb}else{'Localizar automaticamente'}
    if(Test-Path -LiteralPath $SourceText.Text -PathType Container){[void](Scan-SelectedFolder);Invalidate-Plan};Show-Message 'Configuração importada e interface atualizada.'
}

function Choose-FavoriteFolder {
    $favorites=@($script:Settings.Favorites | Where-Object { Test-Path -LiteralPath $_ -PathType Container })
    if(-not $favorites.Count){Show-Message 'Nenhuma pasta favorita configurada. Use Regras e formatos para adicioná-las.';return}
    $form=New-Object Windows.Forms.Form; $form.Text='Pastas favoritas';$form.Width=620;$form.Height=330;$form.StartPosition='CenterParent';$form.Font=New-Object Drawing.Font('Arial',9);$form.BackColor=[Drawing.Color]::FromArgb(195,195,195);$form.ForeColor=[Drawing.Color]::FromArgb(20,20,20)
    $list=New-Object Windows.Forms.ListBox;$list.Dock='Fill';$list.BackColor=[Drawing.Color]::FromArgb(232,232,232);$list.ForeColor=[Drawing.Color]::FromArgb(20,20,20);$list.Items.AddRange([object[]]$favorites);$form.Controls.Add($list)
    $button=New-Object Windows.Forms.Button;$button.Text='Usar pasta selecionada';$button.Dock='Bottom';$button.Height=38;$button.DialogResult='OK';$form.Controls.Add($button);$form.AcceptButton=$button;Set-CrivoFormStyle -Form $form -Title 'Pastas favoritas'
    if($form.ShowDialog() -eq [Windows.Forms.DialogResult]::OK -and $list.SelectedItem){Load-SourceFolder -Path ([string]$list.SelectedItem)}
}

function Select-HistoryOperation {
    $operations=@(Get-OperationHistory | Where-Object { -not $_.UndoneAt }); if(-not $operations.Count){return $null}
    $form=New-Object Windows.Forms.Form;$form.Text='Escolha uma execução para desfazer';$form.Width=760;$form.Height=380;$form.StartPosition='CenterParent';$form.Font=New-Object Drawing.Font('Arial',9);$form.BackColor=[Drawing.Color]::FromArgb(195,195,195);$form.ForeColor=[Drawing.Color]::FromArgb(20,20,20)
    $list=New-Object Windows.Forms.ListBox;$list.Dock='Fill';$list.BackColor=[Drawing.Color]::FromArgb(232,232,232);$list.ForeColor=[Drawing.Color]::FromArgb(20,20,20);foreach($op in $operations){[void]$list.Items.Add(("{0} | {1} | {2} → {3}" -f $op.Date,$op.Action,$op.Source,$op.Destination))};$form.Controls.Add($list)
    $button=New-Object Windows.Forms.Button;$button.Text='Desfazer selecionada';$button.Dock='Bottom';$button.Height=38;$button.DialogResult='OK';$form.Controls.Add($button);$form.AcceptButton=$button;Set-CrivoFormStyle -Form $form -Title 'Escolher execução para desfazer'
    if($form.ShowDialog() -eq [Windows.Forms.DialogResult]::OK -and $list.SelectedIndex -ge 0){return $operations[$list.SelectedIndex]}; return $null
}

function Load-SourceFolder {
    param([Parameter(Mandatory)][string]$Path)
    if(-not (Test-Path -LiteralPath $Path -PathType Container)){return}
    $SourceText.Text=$Path; $script:CustomPlaylistName=Get-DefaultOrganizerPlaylistName -Path $Path; $OrganizerPlaylistNameText.Text=$script:CustomPlaylistName; $DestinationText.Text='Escolha onde salvar a organização'; $script:DestinationChosen=$false
    $DestinationSame.IsChecked=$false; $DestinationOther.IsChecked=$false; $ChooseDestinationButton.IsEnabled=$false
    $ConfigPanel.IsEnabled=$true; $ConfigPanel.Opacity=1; $script:Plan=$null; $script:Tracks=@(); $PreviewGrid.ItemsSource=@()
    $PlanSummary.Text='Analisando a pasta selecionada…'; Set-Status 'Pasta selecionada — iniciando análise' 0; [void](Scan-SelectedFolder);Sync-OrganizerPlaylistName
    $script:WatchSnapshot=@{}; foreach($file in @(Get-WatchCandidates -Source $Path)){$script:WatchSnapshot[$file.FullName]=$true}
}

$ChooseFolderButton.Add_Click({
    $selected = Select-Folder 'Escolha a pasta da pesquisa' ''
    if ($selected) { Load-SourceFolder -Path $selected }
})
$DestinationSame.Add_Checked({
    if (Test-Path -LiteralPath $SourceText.Text -PathType Container) {
        $DestinationText.Text=Join-Path $SourceText.Text 'Pesquisa Organizada'; $script:DestinationChosen=$true; $ChooseDestinationButton.IsEnabled=$false; Invalidate-Plan
    }
})
$DestinationOther.Add_Checked({
    $script:DestinationChosen=$false; $DestinationText.Text='Escolha outro diretório…'; $ChooseDestinationButton.IsEnabled=$true; $script:Plan=$null; $ApplyButton.IsEnabled=$false; $PlanSummary.Text='Clique no botão ao lado para escolher o diretório de destino.'
})
$ChooseDestinationButton.Add_Click({
    $selected=Select-Folder 'Escolha a pasta onde a organização será criada' ''
    if($selected){$DestinationText.Text=$selected; $script:DestinationChosen=$true; Invalidate-Plan}
})

foreach ($radio in @($ModeDate,$ModeGenre,$ModeDateGenre,$ModeGenreBpm)) {
    $radio.Add_Checked({ Sync-FolderPattern; Invalidate-Plan })
}
$CustomizeFolderCheck.Add_Click({ Sync-FolderPattern; Invalidate-Plan })
$TemplateVariablesButton.Add_Click({Show-TemplateVariablesDialog})
$FolderPatternText.Add_TextChanged({ Invalidate-Plan;Sync-OrganizerPlaylistName })
foreach ($control in @($RenameFilesCheck,$CreateReportCheck,$CreateRestoreCheck)) { $control.Add_Click({ Invalidate-Plan }) }
$OnlyAudioCheck.Add_Click({if(Test-Path -LiteralPath $SourceText.Text -PathType Container){[void](Scan-SelectedFolder);Invalidate-Plan}})
$DetectDuplicatesCheck.Add_Click({ Update-Duplicates; Invalidate-Plan })
foreach ($combo in @($ActionCombo,$ConflictCombo,$DateSourceCombo,$MissingPolicyCombo)) { $combo.Add_SelectionChanged({ Invalidate-Plan }) }
$DuplicateLevelCombo.Add_SelectionChanged({
    if((Get-SelectedTag $DuplicateLevelCombo) -eq 'Hash' -and $script:Tracks.Count){[void](Scan-SelectedFolder -IncludeHash)}else{Update-Duplicates}; Invalidate-Plan
})
$ApplyButton.Add_Click({ Invoke-CurrentPlan })
$SearchText.Add_TextChanged({ Refresh-PreviewFilter })
$OrganizerListFilterCombo.Add_SelectionChanged({ Refresh-PreviewFilter })
$EditTrackMetadataButton.Add_Click({Edit-SelectedOrganizeMetadata})
$PreviewGrid.Add_SelectionChanged({Update-OrganizeMetadataButton})

$UndoButton.Add_Click({
    $operation = Select-HistoryOperation
    if (-not $operation) { Refresh-UndoState; return }
    if (Show-CrivoConfirm -Message "Desfazer a organização de $($operation.Date)?" -Title 'Confirmar desfazer' -ConfirmText 'DESFAZER') {
        $result=@(Undo-Operation -Operation $operation); $errors=@($result | Where-Object Status -in @('Erro','Conflito')).Count; Refresh-UndoState
        Show-Message "Desfazer concluído. $($result.Count-$errors) item(ns) restaurado(s); $errors conflito(s)/erro(s)."
    }
})
$OpenHistoryButton.Add_Click({
    $history=@(Get-OperationHistory); if(-not $history.Count){Show-Message 'Ainda não há execuções registradas.';return}
    $text=@($history | Select-Object -First 20 | ForEach-Object { $count=if($_.PSObject.Properties['Counts']){$_.Counts.Total}else{@($_.Items).Count}; "$($_.Date) | $($_.Action) | $count track(s) | $($_.Destination)" }) -join "`n"
    Show-Message $text 'Histórico de execuções'
})
$SupportCrivoButton.Add_Click({Show-SupportCrivoDialog})
$RulesButton.Add_Click({Show-RulesDialog})
$SystemCheckButton.Add_Click({Show-ODTSystemCheck})
$ExportDiagnosticButton.Add_Click({Export-ODTDiagnostic})
$EnrichMetadataButton.Add_Click({Invoke-OnlineEnrichment})
$DryRunButton.Add_Click({Export-CurrentSimulation})
$FavoritesButton.Add_Click({Choose-FavoriteFolder})
$DashboardButton2.Add_Click({Show-LibraryDashboard})
$ExportConfigButton.Add_Click({Export-Configuration}); $ImportConfigButton.Add_Click({Import-Configuration})
$InboxButton.Add_Click({Open-ODTInbox})
$ImportInboxButton.Add_Click({if(Import-ODTInbox){$MainTabs.SelectedIndex=1}})
$StartDownloadButton.Add_Click({Start-DownloadUrls})
$AddDownloadLinkButton.Add_Click({if((Add-DownloadLinksToGrid -Text $DownloadUrlText.Text)-gt 0){$DownloadUrlText.Clear()}})
$DownloadUrlText.Add_KeyDown({param($s,$e);if($e.Key -eq [Windows.Input.Key]::Enter){if((Add-DownloadLinksToGrid -Text $DownloadUrlText.Text)-gt 0){$DownloadUrlText.Clear()};$e.Handled=$true}})
$RemoveDownloadButton.Add_Click({Remove-SelectedDownloadsFromGrid})
$ChooseDownloadDestinationButton.Add_Click({$selected=Select-Folder 'Escolha onde as tracks baixadas serão salvas' (Get-ODTDownloadPath);if($selected){if(-not$script:Settings.Acquisition.PSObject.Properties['DownloadPath']){$script:Settings.Acquisition|Add-Member NoteProperty DownloadPath $selected}else{$script:Settings.Acquisition.DownloadPath=$selected};Save-Settings;$DownloadDestinationText.Text=$selected;$updated=Sync-PendingDownloadDestination -Path $selected;Update-ContextInformation;if($updated){$DownloadStatusText.Text="Destino atualizado para $updated item(ns) que ainda não começaram."}}})
$ClearDownloadsButton.Add_Click({for($i=$script:DownloadQueue.Count-1;$i -ge 0;$i--){if($script:DownloadQueue[$i].Status -in @('Concluido','Expandida')){$script:DownloadQueue.RemoveAt($i)}};$DownloadQueueGrid.Items.Refresh();Update-ContextInformation})
$DownloadQueueGrid.Add_PreviewDragOver({param($s,$e);$hasLink=$e.Data.GetDataPresent([Windows.DataFormats]::UnicodeText) -or $e.Data.GetDataPresent([Windows.DataFormats]::Text) -or $e.Data.GetDataPresent('UniformResourceLocatorW') -or $e.Data.GetDataPresent('UniformResourceLocator');if($hasLink){$e.Effects=[Windows.DragDropEffects]::Copy}else{$e.Effects=[Windows.DragDropEffects]::None};$e.Handled=$true})
$DownloadQueueGrid.Add_PreviewDrop({param($s,$e);Add-DroppedDownloadLinks -EventArgs $e;$e.Handled=$true})
$DownloadQueueGrid.Add_PreviewKeyDown({param($s,$e);if($e.Key -eq [Windows.Input.Key]::Delete){Remove-SelectedDownloadsFromGrid;$e.Handled=$true}})
$ImportRekordboxButton.Add_Click({Import-RekordboxMetadataFile})
$ExportRekordboxButton.Add_Click({Export-RekordboxCollection})
$ChooseRekordboxXmlButton.Add_Click({Select-RekordboxIntegrationXml})
$AuditRekordboxButton.Add_Click({Invoke-RekordboxIntegrationAudit})
$AuditLibraryModeButton.Add_Click({Set-AuditMode Library})
$AuditUsbModeButton.Add_Click({Set-AuditMode Usb})
$ChooseAuditUsbButton.Add_Click({Select-RekordboxAuditUsb})
$AuditUsbButton.Add_Click({Invoke-RekordboxUsbIntegrityAudit})
$ExportRekordboxAuditButton.Add_Click({Export-RekordboxIntegrationAuditFile})
$EditAuditMetadataButton.Add_Click({Edit-SelectedAuditMetadata})
$ReviewAuditButton.Add_Click({Show-AuditSelectionReview})
$AuditSearchText.Add_TextChanged({Update-RekordboxAuditView})
$AuditFilterCombo.Add_SelectionChanged({Update-RekordboxAuditView})
$RekordboxAuditGrid.Add_SelectionChanged({Update-AuditSelectionButtons})
$ToolkitChooseUsbButton.Add_Click({Select-ToolkitUsbDevice})
$ToolkitScanUsbButton.Add_Click({Invoke-ToolkitUsbHealth})
$ToolkitExportButton.Add_Click({Export-ToolkitUsbHealth})
$ToolkitFirstAidButton.Add_Click({Show-ToolkitRecoveryReview})
$ToolkitCompatibilityButton.Add_Click({Invoke-ToolkitCompatibility})
$ToolkitOpenEquipmentSourceButton.Add_Click({if($ToolkitOpenEquipmentSourceButton.Tag){try{Start-Process -FilePath ([string]$ToolkitOpenEquipmentSourceButton.Tag)|Out-Null}catch{Show-Message $_.Exception.Message 'Não foi possível abrir a documentação' Error}}})
$EquipmentProfileCombo.Add_SelectionChanged({
    $script:UsbCompatibilityReport=$null;$CompatibilityChecksGrid.ItemsSource=@()
    $ToolkitOpenEquipmentSourceButton.IsEnabled=$false;$ToolkitOpenEquipmentSourceButton.Tag=$null
    $ToolkitCompatibilityStatus.Text=if($script:UsbHealthReport){'Clique em Verificar compatibilidade'}else{'Faça primeiro o diagnóstico do dispositivo'}
    $ToolkitCompatibilityButton.IsEnabled=($null -ne $script:UsbHealthReport -and $null -ne $EquipmentProfileCombo.SelectedItem)
})
$ToolkitChooseBackupDestinationButton.Add_Click({Select-ToolkitBackupDestination})
$ToolkitCreateBackupButton.Add_Click({Invoke-ToolkitSafeBackup})
$ChooseRekordboxExeButton.Add_Click({Select-RekordboxExecutable})
$SendRekordboxCheck.Add_Click({Sync-OrganizerPlaylistName})
$PlaylistNameFromFolderRadio.Add_Checked({Sync-OrganizerPlaylistName})
$PlaylistNameCustomRadio.Add_Checked({Sync-OrganizerPlaylistName})
$OrganizerPlaylistNameText.Add_TextChanged({if($PlaylistNameCustomRadio.IsChecked -and -not[string]::IsNullOrWhiteSpace($OrganizerPlaylistNameText.Text)){$script:CustomPlaylistName=$OrganizerPlaylistNameText.Text.Trim()}})
$WatchFolderCheck.Add_Click({$script:Settings.WatchFolderEnabled=[bool]$WatchFolderCheck.IsChecked;Save-Settings})
$PreviewGrid.Add_CellEditEnding({
    param($sender,$eventArgs)
    $capturedItem=$eventArgs.Row.Item; $capturedHeader=[string]$eventArgs.Column.Header
    $action={ if($capturedHeader -eq 'GÊNERO'){$capturedItem.MissingGenre=[string]::IsNullOrWhiteSpace([string]$capturedItem.Genre)}; if($capturedHeader -ne 'DESTINO'){Invalidate-Plan}else{$PlanSummary.Text='Destino ajustado manualmente — a validação será feita ao organizar.'} }.GetNewClosure()
    $window.Dispatcher.BeginInvoke([Action]$action,[Windows.Threading.DispatcherPriority]::Background) | Out-Null
})
$window.Add_DragOver({param($s,$e);if($e.Data.GetDataPresent([Windows.DataFormats]::FileDrop)){$e.Effects=[Windows.DragDropEffects]::Copy}else{$e.Effects=[Windows.DragDropEffects]::None};$e.Handled=$true})
$window.Add_Drop({param($s,$e);$paths=@($e.Data.GetData([Windows.DataFormats]::FileDrop));if($paths.Count -and (Test-Path -LiteralPath $paths[0] -PathType Container)){Load-SourceFolder -Path $paths[0]}})
$window.Add_PreviewKeyDown({param($s,$e);if($MainTabs.SelectedIndex -eq 0 -and -not$DownloadUrlText.IsKeyboardFocusWithin -and $e.Key -eq [Windows.Input.Key]::V -and [Windows.Input.Keyboard]::Modifiers.HasFlag([Windows.Input.ModifierKeys]::Control)){try{if([Windows.Clipboard]::ContainsText()){if((Add-DownloadLinksToGrid -Text ([Windows.Clipboard]::GetText())) -gt 0){$e.Handled=$true}}}catch{Write-AppLog -Message $_.Exception.ToString() -Level WARN}}})
$MainTabs.Add_SelectionChanged({param($s,$e);if($e.OriginalSource -eq $MainTabs){Update-ContextInformation}})
$window.Add_Activated({Update-ContextInformation})

$DownloadQueueGrid.ItemsSource=$script:DownloadQueue
$script:DownloadTimer=New-Object Windows.Threading.DispatcherTimer;$script:DownloadTimer.Interval=[TimeSpan]::FromMilliseconds(700)
$script:DownloadTimer.Add_Tick({
    try{
        $newRequests=New-Object Collections.Generic.List[object];$resolvedContainers=New-Object Collections.Generic.List[object]
        for($i=0;$i -lt$script:DownloadQueue.Count;$i++){
            $item=$script:DownloadQueue[$i]
            if($item.Kind -in @('SpotifyResolver','PlaylistResolver') -and $item.Status -eq 'Analisando'){
                $item.ProgressValue=[Math]::Min(90,([int]$item.ProgressValue+5));$item.Progress="$($item.ProgressValue)%"
                [object[]]$resolved=if($item.Kind -eq 'SpotifyResolver'){@(Complete-ODTSpotifyResolver -Resolver $item)}else{@(Complete-ODTPlaylistResolver -Resolver $item)}
                [object[]]$resolved=@($resolved|Where-Object{$null -ne $_})
                # No Windows PowerShell 5.1, @($null).Count pode disparar
                # PropertyNotFoundException dentro de um evento do Dispatcher.
                # Measure-Object mantém o mesmo resultado sem derrubar a fila
                # enquanto o processo ainda não terminou.
                $resolvedCount=($resolved|Measure-Object).Count
                if($resolvedCount -gt 0){$pendingItems=New-Object Collections.Generic.List[object];foreach($request in @($resolved)){$pendingItems.Add($request)};$item|Add-Member NoteProperty PendingItems $pendingItems -Force;$item.Status='Expandindo';$item.ProgressValue=100;$item.Progress='100%';$item.Detail='Adicionando tracks à lista'}
            }
            elseif($item.Kind -in @('SpotifyResolver','PlaylistResolver') -and $item.Status -eq 'Expandindo'){
                # Uma playlist de apenas uma faixa é desembrulhada como objeto
                # escalar pelo Windows PowerShell 5.1. Recriar o array a cada
                # ciclo evita depender de .Count ou RemoveAt nesse objeto.
                $pendingItems=New-Object Collections.ArrayList
                if($item.PSObject.Properties['PendingItems']){
                    $pendingSource=$item.PendingItems
                    foreach($pending in $pendingSource){[void]$pendingItems.Add($pending)}
                }
                if($pendingItems.Count -gt 0){
                    $newRequests.Add($pendingItems[0])
                    $pendingItems.RemoveAt(0)
                    $item.PendingItems=$pendingItems
                }else{$item.Status='Expandida';$item.Detail='Tracks adicionadas à lista';$resolvedContainers.Add($item)}
            }
            elseif($item.Kind -eq 'Download' -and $item.Status -eq 'Baixando'){try{[void](Get-ODTDownloadProgress -Download $item)}catch{$item.Status='Falhou';$item.Detail="Falha ao atualizar: $($_.Exception.Message)";Write-AppLog -Message $_.Exception.ToString() -Level ERROR}}
            elseif($item.Kind -eq 'SpotifySourceResolver' -and $item.Status -eq 'Buscando fonte'){
                try{
                    $resolvedSource=Complete-ODTSpotifySourceResolver -Resolver $item
                    if($resolvedSource.Kind -eq 'Download'){$script:DownloadQueue[$i]=$resolvedSource}
                    elseif($resolvedSource.Status -eq 'Buscando fonte'){$resolvedSource.ProgressValue=[Math]::Min(25,[int]$resolvedSource.ProgressValue+1);$resolvedSource.Progress="$($resolvedSource.ProgressValue)%"}
                }catch{$item.Status='Falhou';$item.Progress='';$item.ProgressValue=0;$item.Detail=$_.Exception.Message;Write-AppLog -Message $_.Exception.ToString() -Level ERROR}
            }
        }
        # Resolver e download são independentes do Rekordbox. A auditoria fará a
        # conferência de duplicatas/presença depois, sem bloquear esta fila.
        foreach($request in $newRequests){if($script:DownloadStartRequested -and $request.IsSelected){$request.Status='Pendente';$request.Progress='0%';$request.ProgressValue=0;$request.Detail='Aguardando vaga para baixar'};$script:DownloadQueue.Add($request)}
        foreach($container in $resolvedContainers){[void]$script:DownloadQueue.Remove($container)}
        $activeDownloads=@($script:DownloadQueue|Where-Object{$_.Status -in @('Baixando','Buscando fonte')}).Count
        $engine=Get-ODTDownloaderPath;$spotifyEngine=Get-ODTSpotifyResolverPath;$ffmpeg=Get-ODTFFmpegPath
        for($i=0;$i -lt$script:DownloadQueue.Count -and $activeDownloads -lt 2;$i++){
            $request=$script:DownloadQueue[$i];if($request.Status -eq 'Pendente' -and -not$request.IsSelected){$request.Status='Pronto';$request.Progress='';$request.Detail='Desmarcada — clique em Iniciar download quando quiser';continue};if($request.Status -ne 'Pendente'){continue}
            try{$currentRoot=Get-ODTDownloadPath;if(-not(Test-Path -LiteralPath $currentRoot -PathType Container)){[IO.Directory]::CreateDirectory($currentRoot)|Out-Null};$request.OutputFolder=$currentRoot;$initialSource=if($request.PSObject.Properties['Artist'] -and $request.Artist){[string]$request.Artist}else{[string]$request.Source};$provider=if($request.PSObject.Properties['Artist']){[string]$request.Source}else{''};$thumbnail=if($request.PSObject.Properties['Thumbnail']){[string]$request.Thumbnail}else{''};if($request.PSObject.Properties['SpotifySourceUrl'] -and $request.SpotifySourceUrl){$started=Start-ODTSpotifySourceResolver -SpotifyUrl ([string]$request.SpotifySourceUrl) -OutputRoot $currentRoot -SpotifyEnginePath $spotifyEngine -DownloadEnginePath $engine -FFmpegPath $ffmpeg -Quality '320' -Title ([string]$request.Title) -Artist $initialSource -Duration ([string]$request.Duration) -Thumbnail $thumbnail}else{$started=Start-ODTDownload -Url $request.DownloadUrl -DisplayUrl $request.Url -InitialTitle $request.Title -InitialSource $initialSource -Provider $provider -InitialDuration $request.Duration -InitialThumbnail $thumbnail -OutputRoot $currentRoot -EnginePath $engine -FFmpegPath $ffmpeg -Quality '320'};$started.IsSelected=$true;$script:DownloadQueue[$i]=$started;$activeDownloads++}catch{$request.Status='Falhou';$request.Progress='0%';$request.ProgressValue=0;$request.Detail="Não foi possível iniciar no destino selecionado: $($_.Exception.Message)";Write-AppLog -Message $_.Exception.ToString() -Level ERROR}
        }
        $active=@($script:DownloadQueue|Where-Object{$_.Status -in @('Baixando','Buscando fonte','Analisando','Expandindo','Pendente')}).Count;$done=@($script:DownloadQueue|Where-Object{$_.Status -eq 'Concluido'}).Count;$failed=@($script:DownloadQueue|Where-Object{$_.Status -in @('Falhou','Link privado')}).Count
        $DownloadQueueGrid.Items.Refresh();$DownloadStatusText.Text="$active em andamento | $done concluído(s) | $failed falha(s)";if($MainTabs.SelectedIndex -eq 0){$StatusText.Text="BAIXAR • $active EM ANDAMENTO • $done CONCLUÍDA(S) • $failed FALHA(S)"};if($active -eq 0 -and -not @($script:DownloadQueue|Where-Object{$_.Status -in @('Buscando fonte','Analisando','Expandindo','Pendente')}).Count){$script:DownloadStartRequested=$false;$script:DownloadTimer.Stop();Update-ContextInformation}
    }catch{
        $diagnostic=$_.Exception.ToString()
        if($_.InvocationInfo -and $_.InvocationInfo.PositionMessage){$diagnostic+="`n$($_.InvocationInfo.PositionMessage)"}
        if($_.ScriptStackTrace){$diagnostic+="`nSTACK:`n$($_.ScriptStackTrace)"}
        Write-AppLog -Message $diagnostic -Level ERROR
        $script:DownloadTimer.Stop();$DownloadStatusText.Text='A fila encontrou um erro. Consulte o log.'
    }
})

$watchTimer=New-Object Windows.Threading.DispatcherTimer; $watchTimer.Interval=[TimeSpan]::FromSeconds(5)
$watchTimer.Add_Tick({
    if(-not $WatchFolderCheck.IsChecked -or -not (Test-Path -LiteralPath $SourceText.Text -PathType Container)){return}
    $current=@(Get-WatchCandidates -Source $SourceText.Text)
    $new=@($current | Where-Object { -not $script:WatchSnapshot.ContainsKey($_.FullName) })
    if($new.Count){Set-Status "$($new.Count) nova(s) música(s) pendente(s) — atualizando análise" 0;[void](Scan-SelectedFolder);if($script:DestinationChosen){Invalidate-Plan};$script:WatchSnapshot=@{};foreach($file in @(Get-WatchCandidates -Source $SourceText.Text)){$script:WatchSnapshot[$file.FullName]=$true}}
});$watchTimer.Start()

$TitleBar.Add_MouseLeftButtonDown({
    param($sender,$eventArgs)
    if ($eventArgs.ClickCount -eq 2) {
        $window.WindowState = if ($window.WindowState -eq [Windows.WindowState]::Maximized) { [Windows.WindowState]::Normal } else { [Windows.WindowState]::Maximized }
    } else {
        try { $window.DragMove() } catch { }
    }
})
$MinimizeButton.Add_Click({ $window.WindowState = [Windows.WindowState]::Minimized })
$CloseButton.Add_Click({ $window.Close() })
$window.Dispatcher.Add_UnhandledException({param($sender,$eventArgs);try{Write-AppLog -Message $eventArgs.Exception.ToString() -Level ERROR;Show-Message $eventArgs.Exception.Message 'O CRIVO DJ recuperou um erro da interface' Error;$eventArgs.Handled=$true}catch{}})

Select-ComboTag $DuplicateLevelCombo ([string]$script:Settings.DuplicateLevel)
Select-ComboTag $MissingPolicyCombo ([string]$script:Settings.MissingMetadataPolicy)
Initialize-ToolkitEquipmentProfiles
$WatchFolderCheck.IsChecked=if($script:Settings.PSObject.Properties['WatchFolderEnabled']){[bool]$script:Settings.WatchFolderEnabled}else{$false}
$configuredRekordbox='';if($script:Settings.PSObject.Properties['Rekordbox'] -and $script:Settings.Rekordbox.PSObject.Properties['ExecutablePath']){$configuredRekordbox=[Environment]::ExpandEnvironmentVariables([string]$script:Settings.Rekordbox.ExecutablePath)};$RekordboxExeText.Text=if($configuredRekordbox){$configuredRekordbox}else{'Localizar automaticamente'}
try{$RekordboxXmlText.Text=Get-RekordboxDatabasePath;$RekordboxSummaryText.Text='Base do Rekordbox detectada. Clique em Escanear biblioteca.'}catch{$RekordboxXmlText.Text='master.db não localizado — clique em Escolher outra'}
try{$removable=@(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=2' -ErrorAction Stop|Where-Object{$_.DeviceID}|Select-Object -First 1);if($removable.Count){$AuditUsbPathText.Text=[string]$removable[0].DeviceID+'\'}}catch{}
if(Test-Path -LiteralPath $AuditUsbPathText.Text -PathType Container){$ToolkitUsbPathText.Text=$AuditUsbPathText.Text}
Refresh-UndoState
Update-ODTEnvironmentStatus|Out-Null
if ($ValidateOnly) {
    if (-not $window.Icon) { throw 'O ícone próprio do CRIVO DJ não foi carregado na janela.' }
    $tabOrder=@($MainTabs.Items|ForEach-Object{[string]$_.Header}) -join '|';if($tabOrder -ne 'BAIXAR|ORGANIZAR|AUDITORIA|KIT DE FERRAMENTAS USB'){throw "Ordem de abas inválida: $tabOrder"}
    if(-not$SourceText -or -not$SendRekordboxCheck -or -not$OrganizerPlaylistNameText -or -not$PlaylistNameFromFolderRadio -or -not$PlaylistNameCustomRadio -or -not$TemplateVariablesButton -or -not$OrganizerListFilterCombo -or -not$EditTrackMetadataButton -or -not$AuditLibraryModeButton -or -not$AuditUsbModeButton -or -not$AuditUsbPathText -or -not$AuditFilterCombo -or -not$EditAuditMetadataButton -or -not$ReviewAuditButton -or -not$AuditDuplicateCount -or -not$ToolkitSubTabs -or -not$ToolkitUsbPathText -or -not$ToolkitScanUsbButton -or -not$ToolkitChecksGrid -or -not$ToolkitExportButton -or -not$EquipmentProfileCombo -or -not$ToolkitCompatibilityButton -or -not$CompatibilityChecksGrid -or -not$ToolkitOpenEquipmentSourceButton -or -not$ToolkitBackupDestinationText -or -not$ToolkitCreateBackupButton -or -not$ToolkitRecoveryStatusText -or -not$SystemCheckButton -or -not$ExportDiagnosticButton -or -not$EnvironmentStatusText){throw 'Controles do fluxo Baixar > Organizar > Auditoria > Kit de ferramentas USB não foram carregados.'}
    $toolkitOrder=@($ToolkitSubTabs.Items|ForEach-Object{[string]$_.Header}) -join '|';if($toolkitOrder -ne 'DIAGNÓSTICO|CÓPIA SEGURA|RECUPERAÇÃO|COMPATIBILIDADE'){throw "Ordem das ferramentas inválida: $toolkitOrder"}
    if($EquipmentProfileCombo.Items.Count -lt 1){throw 'O catálogo de equipamentos não foi carregado.'}
    $queue=New-Object 'Collections.Generic.Queue[Windows.DependencyObject]';$queue.Enqueue($ToolkitRoot);$lightToolkitText=New-Object Collections.Generic.List[string]
    while($queue.Count){$node=$queue.Dequeue();if($node -is [Windows.Controls.TextBlock] -and $node.Foreground -is [Windows.Media.SolidColorBrush]){$color=$node.Foreground.Color;if($color.R -gt 220 -and $color.G -gt 220 -and $color.B -gt 220){$lightToolkitText.Add([string]$node.Text)}};foreach($child in @([Windows.LogicalTreeHelper]::GetChildren($node))){if($child -is [Windows.DependencyObject]){$queue.Enqueue($child)}}}
    if($lightToolkitText.Count){throw "O Kit de ferramentas USB contém texto claro sobre fundo claro: $($lightToolkitText -join ' | ')"}
    if([string]$ToolkitFirstAidButton.Content -ne 'REVISAR RECUPERAÇÃO' -or $ToolkitFirstAidButton.IsEnabled){throw 'A recuperação deve permanecer clara e bloqueada antes da validação do backup.'}
    if($window.Title -ne 'CRIVO DJ por MANELZ0RD'){throw 'O título final do CRIVO DJ não foi aplicado.'}
    $auditHeaders=@($RekordboxAuditGrid.Columns|ForEach-Object{[string]$_.Header});foreach($header in @('ÁLBUM','GÊNERO','ANO','BPM','TONALIDADE','FORMATO','BITRATE','SAMPLE RATE','PLAYLIST(S)','ANÁLISE','PROBLEMA','DUPLICIDADE','PASTA ORIGEM','NÍVEL','DIAGNÓSTICO','LOCAL')){if($auditHeaders -notcontains $header){throw "A coluna de auditoria '$header' não foi carregada."}}
    $ConfigPanel.IsEnabled=$true
    $ModeGenreBpm.IsChecked=$true; Sync-FolderPattern
    if ($FolderPatternText.Text -ne '{GENERO} - {BPM_RANGE}') { throw 'O modelo de pasta não acompanhou o critério Gênero + BPM.' }
    if ($TemplateVariablesButton.IsEnabled) { throw 'O botão de variáveis ficou disponível sem ativar a personalização.' }
    $CustomizeFolderCheck.IsChecked=$true; Sync-FolderPattern; $FolderPatternText.Text='Minha pesquisa'
    if (-not $TemplateVariablesButton.IsEnabled) { throw 'O botão de variáveis não foi liberado pela personalização.' }
    if (Get-TemplateCriteriaError -Template $FolderPatternText.Text) { throw 'Um nome livre sem variáveis foi recusado.' }
    $FolderPatternText.Text='Estilo - {GENERO}\Faixa - {BPM_RANGE}'
    if (Get-TemplateCriteriaError -Template $FolderPatternText.Text) { throw 'Um modelo personalizado com variáveis foi recusado.' }
    $CustomizeFolderCheck.IsChecked=$false; $ModeDateGenre.IsChecked=$true; Sync-FolderPattern
    if ($ValidationSource) {
        $SourceText.Text=$ValidationSource; $DestinationText.Text='Escolha onde salvar a organização'; $ConfigPanel.IsEnabled=$true; $ConfigPanel.Opacity=1
        $OrganizerPlaylistNameText.Text=Get-DefaultOrganizerPlaylistName -Path $ValidationSource
        if (-not (Scan-SelectedFolder)) { throw 'A validação do fluxo de seleção da pasta falhou.' }
        $expectedPlaylistName=Get-DefaultOrganizerPlaylistName -Path $ValidationSource
        if($OrganizerPlaylistNameText.Text -ne $expectedPlaylistName){throw 'O nome automático da playlist não acompanhou a pasta selecionada.'}
        if ($TotalCount.Text -ne [string]$script:Tracks.Count -or $PreviewGrid.Items.Count -ne $script:Tracks.Count) { throw 'Os indicadores ou a tabela não foram atualizados após a seleção.' }
        $DestinationSame.IsChecked=$true
        if (-not $script:Plan -or -not $ApplyButton.IsEnabled) { throw 'O destino no próprio diretório não calculou a organização automaticamente.' }
        $expectedRoot=[IO.Path]::GetFullPath((Join-Path $ValidationSource 'Pesquisa Organizada'))
        if (@($script:Plan.Items | Where-Object { -not $_.Destination.StartsWith($expectedRoot) }).Count) { throw 'A organização não respeitou o destino no próprio diretório.' }
        $generatedFolder=Split-Path (Split-Path $script:Plan.Items[0].Destination -Parent) -Leaf
        if ($generatedFolder -notmatch '^\d{4} - \d{2} - .+ - .+$') { throw "A pasta gerada não reuniu todas as variáveis de Data + Gênero: $generatedFolder" }
        $DestinationOther.IsChecked=$true; $DestinationText.Text=Join-Path $ValidationSource 'Destino Externo'; $script:DestinationChosen=$true
        if (-not (Update-OrganizationPlan)) { throw 'O destino alternativo não calculou a organização.' }
        Write-Output "FOLDER AND DESTINATION FLOW OK: $($script:Tracks.Count) arquivo(s)"
    }
    foreach($context in @(@(0,'BAIXAR'),@(1,'ORGANIZAR'),@(2,'AUDITORIA'),@(3,'KIT DE FERRAMENTAS USB'))){$MainTabs.SelectedIndex=[int]$context[0];Update-ContextInformation;if(-not$StatusText.Text.StartsWith([string]$context[1])){throw "O rodapé não acompanhou a aba $($context[1])."}}
    $MainTabs.SelectedIndex=0
    Write-Output 'VALIDATION OK'; $window.Close(); return
}
$DownloadDestinationText.Text=Get-ODTDownloadPath
Update-ContextInformation
if($DownloadValidationFile){
    if(-not(Test-Path -LiteralPath $DownloadValidationFile -PathType Leaf)){throw "Arquivo de validação de downloads não encontrado: $DownloadValidationFile"}
    $validationText=[IO.File]::ReadAllText((Resolve-Path -LiteralPath $DownloadValidationFile),[Text.Encoding]::UTF8)
    $expectedLinks=[regex]::Matches($validationText,'https?://[^\s\x00]+').Count
    if((Add-DownloadLinksToGrid -Text $validationText) -ne $expectedLinks){throw 'Nem todos os links da validação foram adicionados à fila.'}
    $deadline=(Get-Date).AddSeconds(120)
    while((Get-Date) -lt $deadline -and @($script:DownloadQueue|Where-Object{$_.Status -in @('Analisando','Expandindo')}).Count){Pump-Ui;Start-Sleep -Milliseconds 100}
    Pump-Ui
    $stuck=@($script:DownloadQueue|Where-Object{$_.Status -in @('Analisando','Expandindo')})
    $failed=@($script:DownloadQueue|Where-Object{$_.Status -eq 'Falhou'})
    if($stuck.Count){throw "Validação de download travou com $($stuck.Count) item(ns): $($DownloadStatusText.Text)"}
    $ready=@($script:DownloadQueue|Where-Object{$_.Status -eq 'Pronto'})
    if(-not$ready.Count){throw "Nenhuma track foi resolvida. Falhas: $(@($failed|ForEach-Object{$_.Detail}) -join ' | ')"}
    $withArtwork=@($ready|Where-Object{-not[string]::IsNullOrWhiteSpace([string]$_.Thumbnail)})
    $withoutArtwork=@($ready|Where-Object{[string]::IsNullOrWhiteSpace([string]$_.Thumbnail) -and $_.Detail -notmatch 'buscada em outra fonte'})
    if($withoutArtwork.Count){throw 'Uma track resolvida ficou sem capa e sem busca alternativa.'}
    if(-not$withArtwork.Count){throw 'Nenhuma fonte retornou capa durante a validação.'}
    Write-Output "DOWNLOAD VALIDATION OK: $($ready.Count) track(s), $($withArtwork.Count) capa(s), $($failed.Count) falha(s), fila liberada"
    $window.Close();return
}
if($MarketingScreenshots){
    if([string]::IsNullOrWhiteSpace($MarketingOutput)){$MarketingOutput=Join-Path $AppRoot 'docs\screenshots'}
    [IO.Directory]::CreateDirectory($MarketingOutput)|Out-Null
    $window.Width=1440;$window.Height=900;$window.WindowStartupLocation=[Windows.WindowStartupLocation]::CenterScreen

    function Save-MarketingScreenshot {
        param([string]$Name)
        Pump-Ui;$window.UpdateLayout();Start-Sleep -Milliseconds 350;Pump-Ui
        $visual=$window.Content
        $width=[Math]::Max(1,[int][Math]::Ceiling($visual.ActualWidth))
        $height=[Math]::Max(1,[int][Math]::Ceiling($visual.ActualHeight))
        $bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap($width,$height,96,96,[Windows.Media.PixelFormats]::Pbgra32)
        $bitmap.Render($visual)
        $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
        $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
        $path=Join-Path $MarketingOutput $Name
        $stream=[IO.File]::Open($path,[IO.FileMode]::Create)
        try{$encoder.Save($stream)}finally{$stream.Dispose()}
        Write-Output $path
    }

    function Get-MarketingBitmap {
        param([string]$Path)
        $image=New-Object Windows.Media.Imaging.BitmapImage
        $image.BeginInit();$image.CacheOption=[Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $image.UriSource=[Uri]::new($Path,[UriKind]::Absolute);$image.EndInit();$image.Freeze()
        return $image
    }

    $demoArtwork=@(
        ([Uri]::new((Join-Path $AppRoot 'Assets\Marketing\midnight-signal.jpg'),[UriKind]::Absolute).AbsoluteUri),
        ([Uri]::new((Join-Path $AppRoot 'Assets\Marketing\low-pressure.jpg'),[UriKind]::Absolute).AbsoluteUri),
        ([Uri]::new((Join-Path $AppRoot 'Assets\Marketing\sunday-service.jpg'),[UriKind]::Absolute).AbsoluteUri),
        ([Uri]::new((Join-Path $AppRoot 'Assets\Marketing\glass-rooms.jpg'),[UriKind]::Absolute).AbsoluteUri)
    )
    $demoDownloads=@(
        [pscustomobject]@{IsSelected=$true;Thumbnail=$demoArtwork[0];Title='Midnight Signal — Aurora Lines';Url='soundcloud.com/aurora-lines/midnight-signal';Source='SoundCloud';Duration='06:18';ProgressValue=100;Progress='100%';Detail='MP3 320 kbps • capa e metadados aplicados';Status='Concluído'},
        [pscustomobject]@{IsSelected=$true;Thumbnail=$demoArtwork[1];Title='Low Pressure — Nilo S.';Url='youtube.com/watch?v=crivo-demo-01';Source='YouTube';Duration='05:42';ProgressValue=100;Progress='100%';Detail='MP3 320 kbps • pronta para organizar';Status='Concluído'},
        [pscustomobject]@{IsSelected=$true;Thumbnail=$demoArtwork[2];Title='Sunday Service (Club Mix) — Mabel Costa';Url='open.spotify.com/track/crivo-demo-02';Source='Spotify';Duration='07:04';ProgressValue=68;Progress='68%';Detail='Baixando áudio • 3,8 MB de 5,6 MB';Status='Baixando'},
        [pscustomobject]@{IsSelected=$true;Thumbnail=$demoArtwork[3];Title='Glass Rooms — Theo Vale';Url='soundcloud.com/theo-vale/glass-rooms';Source='SoundCloud';Duration='06:31';ProgressValue=0;Progress='';Detail='Capa e metadados encontrados • aguardando início';Status='Pronto'}
    )
    $DownloadQueueGrid.ItemsSource=$demoDownloads
    $DownloadDestinationText.Text='C:\Music\CRIVO DJ\Downloads'
    $DownloadStatusText.Text='2 concluídas • 1 em andamento • 1 pronta para baixar'
    $MainTabs.SelectedIndex=0;Update-ContextInformation
    $StatusText.Text='BAIXAR • 4 TRACKS NA FILA • 1 EM ANDAMENTO'

    $window.Show();Pump-Ui
    $DownloadStatusText.Text='2 concluídas • 1 em andamento • 1 pronta para baixar'
    $StatusText.Text='BAIXAR • 4 TRACKS NA FILA • YOUTUBE, SOUNDCLOUD E SPOTIFY'
    Save-MarketingScreenshot '01-baixar-tracks.png'

    $demoOrganize=@(
        [pscustomobject]@{Selected=$true;OutputName='Aurora Lines - Midnight Signal.mp3';Artist='Aurora Lines';Genre='Deep House';MetadataStatus='Dados completos';Destination='2026 - 10 - Outubro\Deep House\120-124 BPM'},
        [pscustomobject]@{Selected=$true;OutputName='Nilo S. - Low Pressure.mp3';Artist='Nilo S.';Genre='UK Garage';MetadataStatus='Dados completos';Destination='2026 - 10 - Outubro\UK Garage\130-134 BPM'},
        [pscustomobject]@{Selected=$true;OutputName='Mabel Costa - Sunday Service (Club Mix).mp3';Artist='Mabel Costa';Genre='House';MetadataStatus='Ano faltante';Destination='2026 - 10 - Outubro\House\125-129 BPM'},
        [pscustomobject]@{Selected=$true;OutputName='Theo Vale - Glass Rooms.mp3';Artist='Theo Vale';Genre='Minimal House';MetadataStatus='Álbum faltante • Ano faltante';Destination='2026 - 10 - Outubro\Minimal House\125-129 BPM'},
        [pscustomobject]@{Selected=$true;OutputName='Luma - Soft Focus.mp3';Artist='Luma';Genre='Tech House';MetadataStatus='Dados completos';Destination='2026 - 10 - Outubro\Tech House\125-129 BPM'},
        [pscustomobject]@{Selected=$true;OutputName='Caio Norte - Afterimage.mp3';Artist='Caio Norte';Genre='House';MetadataStatus='Gênero faltante';Destination='2026 - 10 - Outubro\House\125-129 BPM'}
    )
    $SourceText.Text='C:\Music\Pesquisa Outubro'
    $DestinationText.Text='C:\Music\Pesquisa Outubro\Pesquisa Organizada'
    $ConfigPanel.IsEnabled=$true;$ConfigPanel.Opacity=1
    $PreviewGrid.ItemsSource=$demoOrganize
    $TotalCount.Text='6';$GenreLabel1.Text='TRACKS COM DADOS FALTANTES';$ReadyCount.Text='3';$GenreCounter1.Visibility='Visible'
    $GenreCounter2.Visibility='Collapsed';$GenreCounter3.Visibility='Collapsed'
    $PlanSummary.Text='6 tracks analisadas • 3 prontas • 3 com dados faltantes • nenhuma alteração aplicada'
    $ModeDateGenre.IsChecked=$true;$FolderPatternText.Text='{AAAA} - {MES_NUM} - {MES} - {GENERO}'
    $SendRekordboxCheck.IsChecked=$true;$OrganizerPlaylistNameText.Text='Pesquisa Outubro — Organizado'
    $RekordboxExeText.Text='C:\Program Files\rekordbox\rekordbox.exe'
    $ApplyButton.IsEnabled=$true;$EditTrackMetadataButton.IsEnabled=$true
    $MainTabs.SelectedIndex=1;Update-ContextInformation
    $TotalCount.Text='6';$GenreLabel1.Text='TRACKS COM DADOS FALTANTES';$ReadyCount.Text='3';$GenreCounter1.Visibility='Visible'
    $GenreCounter2.Visibility='Collapsed';$GenreCounter3.Visibility='Collapsed'
    $StatusText.Text='ORGANIZAR • 6 TRACKS • PLANO PRONTO PARA REVISÃO'
    $OrganizerOptionsScroll.ScrollToVerticalOffset(0)
    Pump-Ui
    Save-MarketingScreenshot '02a-organizar-opcoes.png'
    $OrganizerOptionsScroll.ScrollToVerticalOffset(335)
    Pump-Ui
    Save-MarketingScreenshot '02-organizar-biblioteca.png'
    Show-AuditMetadataEditor -Row ([pscustomobject]@{Title='Glass Rooms';Artist='Theo Vale';Album='';Genre='Minimal House';Year='';Bpm='128';Key='2A';Location='C:\Music\Pesquisa Outubro\Theo Vale - Glass Rooms.mp3'}) -CapturePath (Join-Path $MarketingOutput 'metadata-editor.png') | Out-Null

    $demoAudit=@(
        [pscustomobject]@{Title='Midnight Signal';Artist='Aurora Lines';Album='Night Transit';Genre='Deep House';Year='2026';Bpm='123';Key='8A';Codec='MP3';Bitrate='320';SampleRate='44.1 kHz';PlaylistDisplay='Pesquisa Outubro / Warm Up';Analysis='Completa';IssueType='Saudável';DuplicateType='—';SourceFolder='Pesquisa Outubro';FolderDepth='2';Issues='Nenhum problema encontrado';Location='D:\DJ Library\Deep House\Aurora Lines - Midnight Signal.mp3'},
        [pscustomobject]@{Title='Low Pressure';Artist='Nilo S.';Album='Pressure Tools';Genre='UK Garage';Year='2026';Bpm='132';Key='5A';Codec='MP3';Bitrate='320';SampleRate='44.1 kHz';PlaylistDisplay='Pesquisa Outubro / Peak Time';Analysis='Completa';IssueType='Saudável';DuplicateType='—';SourceFolder='UK Garage';FolderDepth='3';Issues='Nenhum problema encontrado';Location='D:\DJ Library\UK Garage\Nilo S. - Low Pressure.mp3'},
        [pscustomobject]@{Title='Sunday Service (Club Mix)';Artist='Mabel Costa';Album='Sunday Service';Genre='House';Year='2026';Bpm='126';Key='10A';Codec='MP3';Bitrate='256';SampleRate='44.1 kHz';PlaylistDisplay='Pesquisa Outubro / Vocals';Analysis='Completa';IssueType='Qualidade suspeita';DuplicateType='—';SourceFolder='Downloads';FolderDepth='4';Issues='Bitrate abaixo do padrão definido';Location='D:\DJ Library\House\Mabel Costa - Sunday Service.mp3'},
        [pscustomobject]@{Title='Glass Rooms';Artist='Theo Vale';Album='';Genre='Minimal House';Year='';Bpm='128';Key='2A';Codec='MP3';Bitrate='320';SampleRate='44.1 kHz';PlaylistDisplay='Pesquisa Outubro / After Hours';Analysis='Completa';IssueType='Dados faltantes';DuplicateType='—';SourceFolder='Minimal';FolderDepth='2';Issues='Álbum e ano não informados';Location='D:\DJ Library\Minimal\Theo Vale - Glass Rooms.mp3'},
        [pscustomobject]@{Title='Soft Focus';Artist='Luma';Album='Soft Focus EP';Genre='Tech House';Year='2025';Bpm='127';Key='7B';Codec='WAV';Bitrate='1411';SampleRate='44.1 kHz';PlaylistDisplay='Pesquisa Outubro / Peak Time; Favoritas';Analysis='Completa';IssueType='Duplicada';DuplicateType='Áudio idêntico';SourceFolder='Tech House';FolderDepth='3';Issues='Mesmo áudio encontrado em duas pastas';Location='D:\DJ Library\Tech House\Luma - Soft Focus.wav'},
        [pscustomobject]@{Title='Afterimage';Artist='Caio Norte';Album='Afterimage';Genre='House';Year='2026';Bpm='125';Key='4A';Codec='AIFF';Bitrate='1411';SampleRate='44.1 kHz';PlaylistDisplay='Pesquisa Outubro / Opening';Analysis='Ausente';IssueType='Análise ausente';DuplicateType='—';SourceFolder='House';FolderDepth='2';Issues='Waveform e beatgrid ainda não gerados';Location='D:\DJ Library\House\Caio Norte - Afterimage.aiff'},
        [pscustomobject]@{Title='Parallel Lines';Artist='Miro';Album='Parallel Lines';Genre='Electro';Year='2024';Bpm='130';Key='11B';Codec='MP3';Bitrate='320';SampleRate='44.1 kHz';PlaylistDisplay='Arquivo / Electro';Analysis='Completa';IssueType='Arquivo ausente';DuplicateType='—';SourceFolder='Arquivo';FolderDepth='3';Issues='O caminho salvo no Rekordbox não foi encontrado';Location='D:\DJ Library\Electro\Miro - Parallel Lines.mp3'}
    )
    $RekordboxXmlText.Text='Biblioteca do Rekordbox detectada • modo somente leitura'
    $RekordboxSummaryText.Text='Escaneamento concluído. Filtre os diagnósticos e revise apenas o que precisa de atenção.'
    $RekordboxAuditGrid.ItemsSource=$demoAudit
    # No material de divulgação, prioriza o diagnóstico em vez de exigir rolagem horizontal.
    $marketingAuditColumns=@{}
    foreach($column in $RekordboxAuditGrid.Columns){
        $marketingAuditColumns[[string]$column.Header]=$column
        $column.Visibility=[Windows.Visibility]::Collapsed
    }
    $marketingAuditLayout=@(
        @{Header='TRACK';Width=220},
        @{Header='ARTISTA';Width=150},
        @{Header='PROBLEMA';Width=155},
        @{Header='DIAGNÓSTICO';Width=290},
        @{Header='PLAYLIST(S)';Width=230},
        @{Header='FORMATO';Width=75},
        @{Header='BITRATE';Width=75}
    )
    for($columnIndex=0;$columnIndex -lt $marketingAuditLayout.Count;$columnIndex++){
        $spec=$marketingAuditLayout[$columnIndex]
        $column=$marketingAuditColumns[$spec.Header]
        $column.Visibility=[Windows.Visibility]::Visible
        $column.DisplayIndex=$columnIndex
        $column.Width=[Windows.Controls.DataGridLength]::new([double]$spec.Width)
    }
    # Os indicadores representam exatamente as sete linhas exibidas na captura.
    $AuditCollectionCount.Text='7';$AuditMissingCount.Text='1';$AuditQualityCount.Text='1';$AuditDataCount.Text='2';$AuditDuplicateCount.Text='1'
    $AuditFilterCombo.SelectedIndex=0;$ExportRekordboxAuditButton.IsEnabled=$true
    $AuditReadOnlyText.Text='A verificação é somente leitura. Nenhuma alteração é aplicada automaticamente.'
    $MainTabs.SelectedIndex=2;Update-ContextInformation
    $StatusText.Text='AUDITORIA • 7 TRACKS • 5 PONTOS PARA REVISÃO'
    Save-MarketingScreenshot '03-auditoria-rekordbox.png'

    $ToolkitUsbPathText.Text='E:\  CRIVO-DEMO • FAT32 • 58,2 GB'
    $demoUsbChecks=@(
        [pscustomobject]@{Name='Dispositivo';Level='OK';Summary='Pendrive removível identificado';Detail='E: CRIVO-DEMO'},
        [pscustomobject]@{Name='Sistema de arquivos';Level='OK';Summary='FAT32 identificado';Detail='Formato amplamente aceito pelos equipamentos comparados'},
        [pscustomobject]@{Name='Espaço livre';Level='Atenção';Summary='Restam 7,8 GB de 58,2 GB';Detail='Há espaço para uso, mas vale acompanhar antes de novas exportações'},
        [pscustomobject]@{Name='Biblioteca do Rekordbox';Level='OK';Summary='Biblioteca encontrada e legível';Detail='Nenhuma alteração foi aplicada ao dispositivo'},
        [pscustomobject]@{Name='Dados de análise';Level='OK';Summary='728 arquivos de análise localizados';Detail='Waveforms e beatgrids foram encontrados'},
        [pscustomobject]@{Name='Leitura dos áudios';Level='OK';Summary='728 tracks puderam ser inspecionadas';Detail='A leitura técnica não substitui a audição completa'},
        [pscustomobject]@{Name='Dados das tracks';Level='Atenção';Summary='12 tracks têm dados incompletos';Detail='Título, artista, álbum, gênero e ano foram conferidos'},
        [pscustomobject]@{Name='Duplicatas';Level='Atenção';Summary='3 possíveis repetições';Detail='O resultado pede revisão humana antes de qualquer decisão'}
    )
    $ToolkitChecksGrid.ItemsSource=$demoUsbChecks
    $ToolkitProblemCount.Text='0';$ToolkitAttentionCount.Text='3';$ToolkitUnknownCount.Text='0'
    $ToolkitOverallText.Text='Dispositivo utilizável com pontos para revisar'
    $ToolkitLimitText.Text='Diagnóstico concluído em modo somente leitura • 728 tracks verificadas'
    $ToolkitExportButton.IsEnabled=$true
    $MainTabs.SelectedIndex=3;$ToolkitSubTabs.SelectedIndex=0;Update-ContextInformation
    $StatusText.Text='KIT USB • DIAGNÓSTICO CONCLUÍDO • 3 PONTOS DE ATENÇÃO'
    Save-MarketingScreenshot '04-kit-usb-diagnostico.png'

    $ToolkitBackupDestinationText.Text='C:\Music\Backups\CRIVO-DEMO-recuperado'
    $ToolkitBackupSummaryText.Text='728 tracks • 18,4 GB • espaço disponível confirmado'
    $ToolkitBackupResultText.Text='Plano pronto: a origem permanecerá somente leitura e cada arquivo será conferido.'
    $ToolkitCreateBackupButton.IsEnabled=$true
    $ToolkitSubTabs.SelectedIndex=1
    $StatusText.Text='KIT USB • CÓPIA SEGURA • 728 TRACKS PRONTAS PARA COPIAR'
    Save-MarketingScreenshot '05-kit-usb-copia-segura.png'

    $ToolkitRecoveryStatusText.Text='14 playlists podem ser reconstruídas • 721 de 728 tracks localizadas'
    $ToolkitFirstAidButton.IsEnabled=$true
    $ToolkitSubTabs.SelectedIndex=2
    $StatusText.Text='KIT USB • RECUPERAÇÃO EM OUTRO LOCAL • REVISÃO DISPONÍVEL'
    Save-MarketingScreenshot '06-kit-usb-recuperacao.png'
    $demoRecoveryPlan=[pscustomobject]@{
        physical_audio_count=728;playlists_recoverable=8;playlists_partial=3;playlists_unconfirmed=1
        playlists=@(
            [pscustomobject]@{path='Warm Up';status='Recuperável';resolved_entries=48;unresolved_entries=0},
            [pscustomobject]@{path='Sunset Session';status='Recuperável';resolved_entries=62;unresolved_entries=0},
            [pscustomobject]@{path='Peak Time';status='Recuperação parcial';resolved_entries=71;unresolved_entries=3},
            [pscustomobject]@{path='After Hours';status='Recuperável';resolved_entries=55;unresolved_entries=0},
            [pscustomobject]@{path='UK Garage';status='Recuperável';resolved_entries=64;unresolved_entries=0},
            [pscustomobject]@{path='Minimal House';status='Recuperação parcial';resolved_entries=58;unresolved_entries=2},
            [pscustomobject]@{path='Vocals';status='Recuperável';resolved_entries=46;unresolved_entries=0},
            [pscustomobject]@{path='New Finds';status='Recuperável';resolved_entries=83;unresolved_entries=0},
            [pscustomobject]@{path='Classics';status='Recuperável';resolved_entries=69;unresolved_entries=0},
            [pscustomobject]@{path='Closing';status='Recuperação parcial';resolved_entries=39;unresolved_entries=1},
            [pscustomobject]@{path='Favorites';status='Recuperável';resolved_entries=77;unresolved_entries=0},
            [pscustomobject]@{path='Arquivo antigo';status='Não foi possível confirmar';resolved_entries=0;unresolved_entries=14}
        )
    }
    Show-ToolkitRecoveryReview -DemoPlan $demoRecoveryPlan -CapturePath (Join-Path $MarketingOutput '06a-revisar-recuperacao.png')

    $demoCompatibility=@(
        [pscustomobject]@{Name='Sistema de arquivos';Level='Compatível';Summary='FAT32';Detail='Dentro do formato documentado'},
        [pscustomobject]@{Name='Biblioteca do Rekordbox';Level='Compatível';Summary='EXPORT.PDB legível';Detail='Estrutura aceita pelo perfil selecionado'},
        [pscustomobject]@{Name='Formatos de áudio';Level='Compatível';Summary='MP3, WAV e AIFF';Detail='728 de 728 tracks dentro dos formatos publicados'},
        [pscustomobject]@{Name='Taxa de amostragem';Level='Compatível';Summary='44,1 kHz e 48 kHz';Detail='Nenhuma track acima do limite documentado'},
        [pscustomobject]@{Name='Integridade da biblioteca';Level='Atenção';Summary='3 possíveis duplicatas';Detail='Não impede a leitura, mas merece revisão'}
    )
    if($EquipmentProfileCombo.Items.Count -gt 0){$EquipmentProfileCombo.SelectedIndex=1}
    $CompatibilityChecksGrid.ItemsSource=$demoCompatibility
    $ToolkitCompatibilityStatus.Text='Compatível com os requisitos publicados para o CDJ-2000NXS2'
    $CompatibilitySourceText.Text='Comparação baseada na documentação oficial da AlphaTheta / Pioneer DJ • revisão de outubro de 2026'
    $ToolkitCompatibilityButton.IsEnabled=$true;$ToolkitOpenEquipmentSourceButton.IsEnabled=$true
    $ToolkitSubTabs.SelectedIndex=3
    $StatusText.Text='KIT USB • COMPATIBILIDADE CONFERIDA • CDJ-2000NXS2'
    Save-MarketingScreenshot '07-kit-usb-compatibilidade.png'

    $window.Close();return
}
$window.ShowDialog() | Out-Null
