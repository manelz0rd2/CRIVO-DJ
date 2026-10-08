#requires -Version 5.1
[CmdletBinding()]
param([switch]$ValidateOnly, [string]$ValidationSource, [string]$DownloadValidationFile)

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
foreach ($module in @('Common','Metadata','Scanner','Duplicates','History','Organizer','Enrichment','Inbox','Downloader','Rekordbox')) {
    Import-Module (Join-Path $AppRoot "Modules\$module.psm1") -Force
}
Import-Module (Join-Path $AppRoot 'Modules\Common.psm1') -Force

$script:AppVersion = '0.9.0-beta.1'
$DefaultSettingsPath = Join-Path $AppRoot 'Config\settings.json'
$SettingsPath = Join-Path (Get-AppDataRoot) 'Config\settings.json'
if(-not(Test-Path -LiteralPath $SettingsPath -PathType Leaf)){
    [IO.Directory]::CreateDirectory((Split-Path -Parent $SettingsPath))|Out-Null
    [IO.File]::Copy($DefaultSettingsPath,$SettingsPath,$false)
}
$script:Settings = Read-JsonFile -Path $SettingsPath
if(-not$script:Settings){throw "A configuração do CRIVO DJ está ausente ou inválida: $SettingsPath"}
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
$script:DownloadQueue = New-Object Collections.ObjectModel.ObservableCollection[object]
$script:DownloadFolderTrackCount = 0
$script:DownloadStartRequested = $false

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
    'SourceText','ChooseFolderButton','ConfigPanel','ModeDate','ModeGenre','ModeDateGenre','ModeGenreBpm',
    'DestinationSame','DestinationOther',
    'FolderPatternText','CustomizeFolderCheck','RenameFilesCheck','DetectDuplicatesCheck','OnlyAudioCheck','CreateReportCheck','CreateRestoreCheck',
    'DestinationText','ChooseDestinationButton','ActionCombo','ConflictCombo','DateSourceCombo','DuplicateLevelCombo','MissingPolicyCombo','WatchFolderCheck','SendRekordboxCheck','OrganizerPlaylistNameText','RekordboxExeText','ChooseRekordboxExeButton',
    'RulesButton','DryRunButton','FavoritesButton','DashboardButton2','ExportConfigButton','ImportConfigButton','EnrichMetadataButton','InboxButton','ImportInboxButton','DownloadStatusText','ImportRekordboxButton','ExportRekordboxButton','SystemCheckButton','ExportDiagnosticButton','EnvironmentStatusText',
    'DownloadDropPanel','DownloadUrlText','AddDownloadLinkButton','DownloadDestinationText','ChooseDownloadDestinationButton','StartDownloadButton','RemoveDownloadButton','ClearDownloadsButton','DownloadQueueGrid',
    'RekordboxXmlText','ChooseRekordboxXmlButton','AuditRekordboxButton','RekordboxSummaryText','RekordboxAuditGrid','ExportRekordboxAuditButton','EditAuditMetadataButton','ReviewAuditButton',
    'AuditLibraryModeButton','AuditUsbModeButton','AuditLibrarySourcePanel','AuditUsbSourcePanel','AuditUsbPathText','ChooseAuditUsbButton','AuditUsbButton','AuditReadOnlyText',
    'AuditCollectionCount','AuditMissingCount','AuditQualityCount','AuditDataCount','AuditDuplicateCount','AuditTotalLabel','AuditMissingLabel','AuditQualityLabel','AuditDataLabel','AuditDuplicateLabel','AuditSearchText','AuditFilterCombo',
    'TotalCount','ReadyCount','NoGenreCount','DuplicateCount','GenreCounter1','GenreCounter2','GenreCounter3','GenreLabel1','GenreLabel2','GenreLabel3','SearchText','MetadataMissingCheck','PreviewGrid','PlanSummary','Progress','EditTrackMetadataButton',
    'ApplyButton','UndoButton','OpenHistoryButton','StatusText'
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

function Show-Message {
    param([string]$Message, [string]$Title = 'CRIVO DJ', [Windows.MessageBoxImage]$Icon = [Windows.MessageBoxImage]::Information)
    [Windows.MessageBox]::Show($window, $Message, $Title, [Windows.MessageBoxButton]::OK, $Icon) | Out-Null
}

function Pump-Ui { [Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action]{}, [Windows.Threading.DispatcherPriority]::Background) }

function Set-Status {
    param([string]$Text, [int]$Percent = -1)
    $StatusText.Text = $Text
    if ($Percent -ge 0) { $Progress.Value = $Percent }
    Pump-Ui
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

function Get-CurrentTemplate { return $FolderPatternText.Text.Trim() }

function Sync-FolderPattern {
    $FolderPatternText.IsReadOnly = -not [bool]$CustomizeFolderCheck.IsChecked
    if (-not $CustomizeFolderCheck.IsChecked) { $FolderPatternText.Text = Get-DefaultTemplate }
}

function Get-TemplateCriteriaError {
    param([string]$Template)
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
    $onlyMissingMetadata = [bool]$MetadataMissingCheck.IsChecked
    $predicate = [Predicate[object]]{
        param($item)
        $trackText = "$($item.Name) $($item.OutputName) $($item.Title)".ToLowerInvariant()
        $matchesSearch = -not $search -or $trackText.Contains($search)
        $hasMissingMetadata = $item.MissingTitle -or -not $item.Artist -or -not $item.Album -or $item.MissingGenre -or -not $item.Genre -or -not $item.Year -or -not $item.Bpm -or -not $item.Key
        return $matchesSearch -and (-not $onlyMissingMetadata -or $hasMissingMetadata)
    }.GetNewClosure()
    $view.Filter = $predicate; $view.Refresh()
}

function Update-Dashboard {
    $health = Get-LibraryHealth -Tracks @($script:Tracks)
    $TotalCount.Text = [string]$health.Total
    $cards = @(
        [pscustomobject]@{ Border=$GenreCounter1; Label=$GenreLabel1; Count=$ReadyCount },
        [pscustomobject]@{ Border=$GenreCounter2; Label=$GenreLabel2; Count=$NoGenreCount },
        [pscustomobject]@{ Border=$GenreCounter3; Label=$GenreLabel3; Count=$DuplicateCount }
    )
    $genres = @($script:Tracks | ForEach-Object {
        $genre = ([string]$_.Genre).Trim()
        if (-not $genre) { $genre = 'SEM GÊNERO' }
        $genre
    } | Group-Object | Sort-Object @{Expression='Count';Descending=$true}, @{Expression='Name';Descending=$false})
    for ($i=0; $i -lt $cards.Count; $i++) {
        if ($i -lt $genres.Count) {
            $cards[$i].Label.Text = ('TRACKS DE {0}' -f ([string]$genres[$i].Name).ToUpperInvariant())
            $cards[$i].Label.ToolTip = $cards[$i].Label.Text
            $cards[$i].Count.Text = [string]$genres[$i].Count
            $cards[$i].Border.Visibility = 'Visible'
        } else {
            $cards[$i].Label.Text = 'TRACKS POR GÊNERO'
            $cards[$i].Count.Text = '0'
            $cards[$i].Border.Visibility = 'Collapsed'
        }
    }
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
        $progressAction = {
            param($current,$total,$name)
            Set-Status "Lendo $name ($current de $total)" $(if($total){[int](($current/$total)*100)}else{0})
        }
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
        Update-Dashboard; Refresh-PreviewFilter
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
    if ([Windows.MessageBox]::Show($window, "Confirmar e $verb $(@($script:Plan.Items | Where-Object Status -eq 'Ready').Count) track(s)?$rekordboxWarning", 'Confirmar organização', [Windows.MessageBoxButton]::YesNo, [Windows.MessageBoxImage]::Question) -ne [Windows.MessageBoxResult]::Yes) { return }
    try {
        $ChooseFolderButton.IsEnabled=$false; $ApplyButton.IsEnabled=$false
        $progressAction = { param($current,$total,$name) Set-Status "Organizando $name ($current de $total)" ([int](($current/[Math]::Max(1,$total))*100)) }
        $result = Invoke-OrganizationPlan -Plan $script:Plan -OnProgress $progressAction
        Set-Status 'Organização concluída' 100; Refresh-UndoState
        $extra = ''; if ($result.ReportPath) { $extra += "`nRelatório: $($result.ReportPath)" }; if ($result.HistoryPath) { $extra += "`nPonto de restauração criado." }
        if($SendRekordboxCheck.IsChecked){try{$rb=Export-OrganizedPlanToRekordbox -Plan $script:Plan -Operation $result.Operation;if($rb){$needsAnalysis=if($rb.Import.PSObject.Properties['tracksNeedingAnalysis']){[int]$rb.Import.tracksNeedingAnalysis}else{0};$analysisText=if($needsAnalysis -gt 0){"`n$needsAnalysis track(s) aguardam a análise oficial do Rekordbox (waveform e beatgrid)."}else{"`nAs tracks já possuem análise do Rekordbox."};$extra+="`nPlaylist Rekordbox '$($rb.PlaylistName)' gravada diretamente e verificada ($($rb.Count) tracks).$analysisText`nBackup: $($rb.Import.BackupPath)"}}catch{Write-AppLog -Message $_.Exception.ToString() -Level ERROR;$extra+="`nFalha na gravação direta do Rekordbox: $($_.Exception.Message)"}}
        $completedCount=$result.Success;$skippedCount=if($result.PSObject.Properties['Skipped']){[int]$result.Skipped}else{0}
        [void](Scan-SelectedFolder);$script:Plan=$null;$ApplyButton.IsEnabled=$false
        $PlanSummary.Text="Organização concluída • $completedCount track(s) processada(s) • $skippedCount ignorada(s) • $($result.Errors) erro(s)"
        Set-Status 'Organização concluída — grid atualizado' 100
        Show-Message "Organização concluída.`n`nProcessadas: $completedCount`nIgnoradas: $skippedCount`nErros: $($result.Errors)$extra" 'Tudo pronto';Update-ContextInformation
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
    $form.Controls.Add($grid);$form.Controls.Add($bottom);$form.Controls.Add($intro);$form.AcceptButton=$apply;$form.CancelButton=$cancel
    if($form.ShowDialog() -ne [Windows.Forms.DialogResult]::OK){return}
    $approved=New-Object Collections.Generic.List[object]
    foreach($row in $grid.Rows){if([bool]$row.Cells[0].Value){$item=$row.Tag;if(Set-TrackSuggestion -Track $item.Track -Suggestion $item.Suggestion -FillOnlyEmpty:(-not$replace.Checked)){$approved.Add($item.Track)}}}
    if(-not$approved.Count){Show-Message 'Nenhum dado encontrado foi marcado para uso.' 'Buscar dados ausentes';return}
    $tagSummary='';if($write.Checked){$tagResult=Write-ApprovedMetadata -Tracks $approved.ToArray();$tagSummary="`nTags gravadas: $($tagResult.Updated)`nErros de gravação: $($tagResult.Errors)`nBackup registrado no histórico."}
    Update-Dashboard;if($script:DestinationChosen){Invalidate-Plan}else{$PreviewGrid.Items.Refresh()};Show-Message "Dados aplicados em $($approved.Count) faixa(s).$tagSummary" 'Dados das faixas atualizados'
}

function Invoke-OnlineEnrichment {
    if(-not$script:Tracks.Count){Show-Message 'Escolha e analise uma pasta primeiro.';return}
    $candidates=@($script:Tracks|Where-Object{$_.Selected -and ($_.MissingTitle -or -not$_.Artist -or -not$_.Album -or $_.MissingGenre -or -not$_.Year)})
    if(-not$candidates.Count){Show-Message 'As faixas selecionadas já possuem título, artista, álbum, gênero e ano.' 'Buscar dados ausentes';return}
    $estimated=[Math]::Ceiling($candidates.Count*2.2/60)
    if([Windows.MessageBox]::Show($window,"Buscar na internet título, artista, álbum, gênero e ano ausentes de $($candidates.Count) faixa(s)?`n`nVocê revisará os resultados antes de aplicar. Nenhum arquivo será alterado nesta etapa.`nTempo estimado: $estimated minuto(s). O áudio não será enviado.",'Buscar dados ausentes',[Windows.MessageBoxButton]::YesNo,[Windows.MessageBoxImage]::Question)-ne[Windows.MessageBoxResult]::Yes){return}
    $matches=New-Object Collections.Generic.List[object];$EnrichMetadataButton.IsEnabled=$false
    try{
        for($i=0;$i -lt$candidates.Count;$i++){$track=$candidates[$i];Set-Status "Buscando dados: $($track.Name) ($($i+1) de $($candidates.Count))" ([int](($i+1)/$candidates.Count*100));$suggestion=Get-OnlineMetadataSuggestion -Track $track -Settings $script:Settings;if($suggestion.Found){$matches.Add([pscustomobject]@{Track=$track;Suggestion=$suggestion})}}
        Set-Status "Busca concluída — dados encontrados para $($matches.Count) faixa(s)" 100
        if($matches.Count){Show-MetadataReview -Matches $matches.ToArray()}else{Show-Message 'Nenhum dado correspondente foi encontrado nas fontes online.' 'Buscar dados ausentes'}
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
    if(-not$files.Count){Show-Message "A Inbox está vazia.`n`nBaixe ou copie as faixas para:`n$path" 'Inbox de downloads';return $false}
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
        Compress-Archive -Path (Join-Path $tempRoot '*') -DestinationPath $dialog.FileName -CompressionLevel Optimal -Force;Show-Message "Diagnóstico exportado sem caminhos pessoais ou chaves:`n$($dialog.FileName)" 'Diagnóstico pronto'
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
            $isSpotify=$url -match '^https?://(open\.)?spotify\.com/';$isSingleSpotify=$url -match '^https?://(open\.)?spotify\.com/track/';$isYouTubeTrack=$url -match '(youtube\.com/watch\?|youtu\.be/)';$isSoundCloudUserPage=$url -match '^https?://(?:www\.)?soundcloud\.com/[\w-]+/?(?:[?#].*)?$';$isPlaylist=(-not$isYouTubeTrack -and $url -match '([?&]list=|/playlist(?:s)?/|/sets?/|/albums?/|/mix(?:es)?/|/collection/|/tracklist/|/shows?/|/channels?/|/series/|/feed/)') -or $isSoundCloudUserPage;$singleTrack=(-not$isPlaylist)
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
    try{[void](Add-DownloadLinksToGrid -Text $DownloadUrlText.Text);$DownloadUrlText.Clear();$ready=@($script:DownloadQueue|Where-Object{$_.Status -eq 'Pronto' -and $_.IsSelected});$analyzing=@($script:DownloadQueue|Where-Object{$_.Status -in @('Analisando','Expandindo')}).Count
        if(-not$ready.Count -and -not$analyzing){$script:DownloadStartRequested=$false;Show-Message 'Marque no grid pelo menos uma track pronta para baixar.' 'Baixar tracks';return}
        $script:DownloadStartRequested=$true
        foreach($request in $ready){$request.QualityCode='320';$request.Quality='MP3 320 kbps';$request.Status='Pendente';$request.Progress='0%';$request.ProgressValue=0;$request.Detail='Aguardando vaga para baixar'}
        $DownloadQueueGrid.Items.Refresh();$DownloadStatusText.Text=$(if($analyzing){'Análise em andamento; as tracks selecionadas iniciarão assim que os dados chegarem.'}else{"$($ready.Count) track(s) adicionada(s) à fila de download."});$script:DownloadTimer.Start()
    }catch{Write-AppLog -Message $_.Exception.ToString() -Level ERROR;Show-Message $_.Exception.Message 'Não foi possível adicionar o link' Error}
}

function Add-DroppedDownloadLinks {
    param($EventArgs)
    try{$text='';foreach($format in @([Windows.DataFormats]::UnicodeText,[Windows.DataFormats]::Text,'UniformResourceLocatorW','UniformResourceLocator')){if($EventArgs.Data.GetDataPresent($format)){try{$data=$EventArgs.Data.GetData($format);if($data -is [IO.MemoryStream]){$reader=New-Object IO.StreamReader($data,[Text.Encoding]::Unicode);$text=$reader.ReadToEnd();$reader.Dispose()}else{$text=[string]$data};if($text){break}}catch{}}};if($text){[void](Add-DownloadLinksToGrid -Text $text)}}catch{Write-AppLog -Message $_.Exception.ToString() -Level ERROR;Show-Message $_.Exception.Message 'Não foi possível interpretar o link arrastado' Error}
}

function Remove-SelectedDownloadsFromGrid {
    $selected=@($DownloadQueueGrid.SelectedItems);if(-not$selected.Count){Show-Message 'Destaque uma ou mais linhas no grid para remover.' 'Remover da fila';return}
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
        $progressAction={param($current,$total,$name);$percent=20+[int][Math]::Round(($current/[Math]::Max(1,$total))*75);Set-Status "Verificando track $current de $total • $name" $percent;if($current -eq 1 -or $current%10 -eq 0 -or $current -eq $total){Pump-Ui}}.GetNewClosure()
        $script:RekordboxLibraryAudit=Get-RekordboxAudit -Library $script:RekordboxLibrary -Settings $script:Settings -OnProgress $progressAction;$script:RekordboxAudit=$script:RekordboxLibraryAudit
        Show-AuditResult $script:RekordboxLibraryAudit;Set-Status 'Auditoria da biblioteca concluída' 100
    }catch{$script:RekordboxLibraryAudit=$null;Clear-AuditDisplay;Write-AppLog -Message $_.Exception.ToString() -Level ERROR;Show-Message $_.Exception.Message 'Falha ao ler o banco do Rekordbox' Error}
}

function Invoke-RekordboxUsbIntegrityAudit {
    $path=[string]$AuditUsbPathText.Text;if(-not(Test-Path -LiteralPath $path -PathType Container)){Show-Message 'Escolha a raiz do pendrive ou dispositivo exportado pelo Rekordbox.' 'Integridade do pendrive';return}
    try{
        Set-Status 'Lendo a estrutura do dispositivo…' 5;Pump-Ui
        $progressAction={param($current,$total,$name);$percent=10+[int][Math]::Round(($current/[Math]::Max(1,$total))*80);Set-Status "Verificando arquivo $current de $total • $name" $percent;if($current -eq 1 -or $current%10 -eq 0 -or $current -eq $total){Pump-Ui}}.GetNewClosure()
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
    param([Parameter(Mandatory)]$Row)
    $form=New-Object Windows.Forms.Form;$form.Text='CRIVO DJ — Adicionar ou corrigir metadados';$form.Width=620;$form.Height=500;$form.StartPosition='CenterParent';$form.FormBorderStyle='FixedDialog';$form.MaximizeBox=$false;$form.MinimizeBox=$false;$form.Font=New-Object Drawing.Font('Arial',9);$form.BackColor=[Drawing.Color]::FromArgb(205,205,205);$form.ForeColor=[Drawing.Color]::Black
    $intro=New-Object Windows.Forms.Label;$intro.Left=18;$intro.Top=15;$intro.Width=570;$intro.Height=46;$intro.ForeColor=[Drawing.Color]::Black;$intro.Text="Preencha somente o que deseja salvar. A track será atualizada no arquivo e, quando fizer parte da coleção, também no Rekordbox com backup prévio.";$form.Controls.Add($intro)
    $fields=[ordered]@{Title='TÍTULO';Artist='ARTISTA';Album='ÁLBUM';Genre='GÊNERO';Year='ANO';Bpm='BPM';Key='TONALIDADE'};$boxes=@{};$top=72
    foreach($field in $fields.Keys){$label=New-Object Windows.Forms.Label;$label.Left=18;$label.Top=$top;$label.Width=110;$label.Height=24;$label.Text=$fields[$field];$label.TextAlign='MiddleLeft';$label.ForeColor=[Drawing.Color]::Black;$form.Controls.Add($label);$box=New-Object Windows.Forms.TextBox;$box.Left=132;$box.Top=$top;$box.Width=445;$box.Height=25;$box.ForeColor=[Drawing.Color]::Black;$box.BackColor=[Drawing.Color]::FromArgb(241,240,236);$value=if($Row.PSObject.Properties[$field]){[string]$Row.$field}else{''};$box.Text=$value;$form.Controls.Add($box);$boxes[$field]=$box;$top+=43}
    $fileLabel=New-Object Windows.Forms.Label;$fileLabel.Left=18;$fileLabel.Top=378;$fileLabel.Width=560;$fileLabel.Height=28;$fileLabel.AutoEllipsis=$true;$fileLabel.ForeColor=[Drawing.Color]::FromArgb(60,60,60);$fileLabel.Text=[string]$Row.Location;$form.Controls.Add($fileLabel)
    $save=New-Object Windows.Forms.Button;$save.Text='SALVAR METADADOS';$save.Left=370;$save.Top=414;$save.Width=135;$save.Height=32;$save.DialogResult='OK';$form.Controls.Add($save)
    $cancel=New-Object Windows.Forms.Button;$cancel.Text='CANCELAR';$cancel.Left=512;$cancel.Top=414;$cancel.Width=75;$cancel.Height=32;$cancel.DialogResult='Cancel';$form.Controls.Add($cancel);$form.AcceptButton=$save;$form.CancelButton=$cancel
    if($form.ShowDialog() -ne [Windows.Forms.DialogResult]::OK){return $null}
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
    $selected=@($PreviewGrid.SelectedItems);if($selected.Count -ne 1){Show-Message 'Selecione uma única track no grid para editar os metadados.' 'Editar metadados';return};$track=$selected[0];$path=[string]$track.FullName
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){Show-Message 'O arquivo físico desta track não está disponível.' 'Editar metadados' Warning;return}
    $metadata=Show-AuditMetadataEditor -Row ([pscustomobject]@{Title=[string]$track.Title;Artist=[string]$track.Artist;Album=[string]$track.Album;Genre=[string]$track.Genre;Year=[string]$track.Year;Bpm=[string]$track.Bpm;Key=[string]$track.Key;Location=$path});if(-not$metadata){return}
    $tagResult=$null;try{$tagResult=Write-ApprovedMetadata -Tracks @([pscustomobject]@{FullName=$path;Title=$metadata.Title;Artist=$metadata.Artist;Album=$metadata.Album;Genre=$metadata.Genre;Year=$metadata.Year;Bpm=$metadata.Bpm;Key=$metadata.Key}) -Template 'Edição manual da organização';if($tagResult.Errors){throw 'Não foi possível gravar os metadados no arquivo.'};foreach($field in @('Title','Artist','Album','Genre','Year','Bpm','Key')){if($metadata.$field){$track.$field=$metadata.$field}};if($track.Title){$track.MissingTitle=$false};if($track.Genre){$track.MissingGenre=$false};$PreviewGrid.Items.Refresh();Update-Dashboard;Refresh-PreviewFilter;Invalidate-Plan;Show-Message 'Metadados salvos no arquivo e no histórico do CRIVO DJ.' 'Metadados atualizados'}catch{if($tagResult -and $tagResult.Updated){try{Undo-Operation -Operation $tagResult.Operation|Out-Null}catch{}};Write-AppLog -Message $_.Exception.ToString() -Level ERROR;Show-Message $_.Exception.Message 'Falha ao salvar metadados' Error}
}

function Show-AuditSelectionReview {
    $selected=@($RekordboxAuditGrid.SelectedItems);if(-not$selected.Count){Show-Message 'Selecione uma ou mais linhas no grid.' 'Revisar auditoria';return}
    $lines=New-Object Collections.Generic.List[string]
    foreach($row in @($selected|Select-Object -First 12)){
        $action=if($row.IssueCategories -match 'Unavailable'){'desbloquear ou reconectar a unidade e escanear novamente'}elseif($row.IssueCategories -match 'Missing'){'localizar novamente o arquivo no Rekordbox'}elseif($row.IssueCategories -match 'Integrity'){'substituir ou copiar novamente o arquivo'}elseif($row.IssueCategories -match 'Quality'){'comparar com uma fonte de melhor qualidade'}elseif($row.IssueCategories -match 'Metadata'){'revisar os campos de metadata'}elseif($row.IssueCategories -match 'Analysis'){'analisar novamente no Rekordbox e reexportar'}elseif($row.IssueCategories -match 'PossibleDuplicate'){'comparar versão, remix, duração e qualidade antes de decidir'}elseif($row.IssueCategories -match '(^|;)Duplicate(;|$)'){'comparar os caminhos e manter apenas a cópia correta'}elseif($row.IssueCategories -match 'Location'){'consolidar numa pasta gerenciada pelo CRIVO e depois relocalizar pelo Rekordbox'}elseif($row.IssueCategories -match 'Structure'){'reexportar ou reparar o dispositivo pelo Rekordbox'}else{'revisar manualmente'}
        $lines.Add("$($row.Title) — $action")
    }
    $extra=if($selected.Count -gt 12){"`n…e mais $($selected.Count-12) item(ns)."}else{''};Show-Message ("REVISÃO RECOMENDADA`n`n"+($lines -join "`n")+$extra+"`n`nNenhuma correção foi aplicada.") 'Revisar auditoria'
}

function Export-RekordboxIntegrationAuditFile {
    if(-not$script:RekordboxAudit){Show-Message 'Execute a auditoria primeiro.' 'Auditoria';return};$dialog=New-Object Windows.Forms.SaveFileDialog;$dialog.Title='Exportar auditoria';$dialog.Filter='CSV (*.csv)|*.csv|JSON (*.json)|*.json';$suffix=if([string]$script:RekordboxAudit.Mode -eq 'Usb'){'Pendrive'}else{'Rekordbox'};$dialog.FileName="CRIVO-DJ-Auditoria-$suffix.csv";if($dialog.ShowDialog() -ne [Windows.Forms.DialogResult]::OK){return};Export-RekordboxAudit -Audit $script:RekordboxAudit -Path $dialog.FileName|Out-Null;Show-Message "Auditoria exportada:`n$($dialog.FileName)" 'Auditoria'
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
    $labels = @('Extensões de áudio (separadas por vírgula)','Extensões ignoradas','Pastas ignoradas','Normalização de gêneros (origem=destino)','Faixas de BPM (mín-máx=nome)','Pastas favoritas','Prioridade sem gênero (Metadata, SourceFolder, _PENDENTE)','Qualidade mínima: bitrate MP3, sample rate','Termos removidos do nome','Chave de cliente AcoustID (opcional)','Confiança mínima para pré-selecionar sugestões (0–100)')
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
    if($form.ShowDialog() -ne [Windows.Forms.DialogResult]::OK){return}
    try {
        $script:Settings.AudioExtensions=@($boxes[0].Text -split '[,;]' | ForEach-Object { $value=$_.Trim().ToLower();if($value -and -not$value.StartsWith('.')){'.'+$value}else{$value} } | Where-Object { $_ })
        $script:Settings.ExcludedExtensions=@($boxes[1].Text -split '[,;]' | ForEach-Object { $value=$_.Trim().ToLower();if($value -and -not$value.StartsWith('.')){'.'+$value}else{$value} } | Where-Object { $_ })
        $script:Settings.ExcludedFolders=@($boxes[2].Text -split '[,;]' | ForEach-Object Trim | Where-Object { $_ })
        $aliases=[ordered]@{}; foreach($line in $boxes[3].Lines){if($line -match '^\s*([^=]+)=(.+)$'){$aliases[$Matches[1].Trim().ToUpperInvariant()]=$Matches[2].Trim()}}
        $ranges=@(); foreach($line in $boxes[4].Lines){if($line -match '^\s*(\d+)\s*-\s*(\d+)\s*=(.+)$'){$ranges += [pscustomobject]@{Min=[int]$Matches[1];Max=[int]$Matches[2];Name=$Matches[3].Trim()}}}
        if($aliases.Count){$script:Settings.GenreAliases=[pscustomobject]$aliases}; if($ranges.Count){$script:Settings.BpmRanges=$ranges}
        $script:Settings.Favorites=@($boxes[5].Lines | ForEach-Object Trim | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) })
        $priority=@($boxes[6].Text -split '[,;]' | ForEach-Object Trim | Where-Object { $_ -in @('Metadata','SourceFolder','_PENDENTE') }); if($priority.Count){$script:Settings.GenreFallbackPriority=$priority}
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
    if($dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK){Export-OrganizationPlan -Plan $script:Plan -Path $dialog.FileName | Out-Null; Show-Message "Simulação exportada sem mover ou copiar arquivos.`n`n$($dialog.FileName)"}
}

function Export-Configuration {
    $dialog=New-Object Windows.Forms.SaveFileDialog; $dialog.Filter='Configuração JSON (*.json)|*.json'; $dialog.FileName='CRIVO-DJ-config.json'
    if($dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK){Write-JsonFile -Path $dialog.FileName -Value $script:Settings;Show-Message 'Configuração exportada.'}
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
    $button=New-Object Windows.Forms.Button;$button.Text='Usar pasta selecionada';$button.Dock='Bottom';$button.Height=38;$button.DialogResult='OK';$form.Controls.Add($button);$form.AcceptButton=$button
    if($form.ShowDialog() -eq [Windows.Forms.DialogResult]::OK -and $list.SelectedItem){Load-SourceFolder -Path ([string]$list.SelectedItem)}
}

function Select-HistoryOperation {
    $operations=@(Get-OperationHistory | Where-Object { -not $_.UndoneAt }); if(-not $operations.Count){return $null}
    $form=New-Object Windows.Forms.Form;$form.Text='Escolha uma execução para desfazer';$form.Width=760;$form.Height=380;$form.StartPosition='CenterParent';$form.Font=New-Object Drawing.Font('Arial',9);$form.BackColor=[Drawing.Color]::FromArgb(195,195,195);$form.ForeColor=[Drawing.Color]::FromArgb(20,20,20)
    $list=New-Object Windows.Forms.ListBox;$list.Dock='Fill';$list.BackColor=[Drawing.Color]::FromArgb(232,232,232);$list.ForeColor=[Drawing.Color]::FromArgb(20,20,20);foreach($op in $operations){[void]$list.Items.Add(("{0} | {1} | {2} → {3}" -f $op.Date,$op.Action,$op.Source,$op.Destination))};$form.Controls.Add($list)
    $button=New-Object Windows.Forms.Button;$button.Text='Desfazer selecionada';$button.Dock='Bottom';$button.Height=38;$button.DialogResult='OK';$form.Controls.Add($button);$form.AcceptButton=$button
    if($form.ShowDialog() -eq [Windows.Forms.DialogResult]::OK -and $list.SelectedIndex -ge 0){return $operations[$list.SelectedIndex]}; return $null
}

function Load-SourceFolder {
    param([Parameter(Mandatory)][string]$Path)
    if(-not (Test-Path -LiteralPath $Path -PathType Container)){return}
    $SourceText.Text=$Path; $OrganizerPlaylistNameText.Text=Get-DefaultOrganizerPlaylistName -Path $Path; $DestinationText.Text='Escolha onde salvar a organização'; $script:DestinationChosen=$false
    $DestinationSame.IsChecked=$false; $DestinationOther.IsChecked=$false; $ChooseDestinationButton.IsEnabled=$false
    $ConfigPanel.IsEnabled=$true; $ConfigPanel.Opacity=1; $script:Plan=$null; $script:Tracks=@(); $PreviewGrid.ItemsSource=@()
    $PlanSummary.Text='Analisando a pasta selecionada…'; Set-Status 'Pasta selecionada — iniciando análise' 0; [void](Scan-SelectedFolder)
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
$FolderPatternText.Add_TextChanged({ Invalidate-Plan })
foreach ($control in @($RenameFilesCheck,$CreateReportCheck,$CreateRestoreCheck)) { $control.Add_Click({ Invalidate-Plan }) }
$OnlyAudioCheck.Add_Click({if(Test-Path -LiteralPath $SourceText.Text -PathType Container){[void](Scan-SelectedFolder);Invalidate-Plan}})
$DetectDuplicatesCheck.Add_Click({ Update-Duplicates; Invalidate-Plan })
foreach ($combo in @($ActionCombo,$ConflictCombo,$DateSourceCombo,$MissingPolicyCombo)) { $combo.Add_SelectionChanged({ Invalidate-Plan }) }
$DuplicateLevelCombo.Add_SelectionChanged({
    if((Get-SelectedTag $DuplicateLevelCombo) -eq 'Hash' -and $script:Tracks.Count){[void](Scan-SelectedFolder -IncludeHash)}else{Update-Duplicates}; Invalidate-Plan
})
$ApplyButton.Add_Click({ Invoke-CurrentPlan })
$SearchText.Add_TextChanged({ Refresh-PreviewFilter })
$MetadataMissingCheck.Add_Click({ Refresh-PreviewFilter })
$EditTrackMetadataButton.Add_Click({Edit-SelectedOrganizeMetadata})
$PreviewGrid.Add_SelectionChanged({Update-OrganizeMetadataButton})

$UndoButton.Add_Click({
    $operation = Select-HistoryOperation
    if (-not $operation) { Refresh-UndoState; return }
    if ([Windows.MessageBox]::Show($window, "Desfazer a organização de $($operation.Date)?", 'Confirmar desfazer', [Windows.MessageBoxButton]::YesNo, [Windows.MessageBoxImage]::Question) -eq [Windows.MessageBoxResult]::Yes) {
        $result=@(Undo-Operation -Operation $operation); $errors=@($result | Where-Object Status -in @('Erro','Conflito')).Count; Refresh-UndoState
        Show-Message "Desfazer concluído. $($result.Count-$errors) item(ns) restaurado(s); $errors conflito(s)/erro(s)."
    }
})
$OpenHistoryButton.Add_Click({
    $history=@(Get-OperationHistory); if(-not $history.Count){Show-Message 'Ainda não há execuções registradas.';return}
    $text=@($history | Select-Object -First 20 | ForEach-Object { $count=if($_.PSObject.Properties['Counts']){$_.Counts.Total}else{@($_.Items).Count}; "$($_.Date) | $($_.Action) | $count track(s) | $($_.Destination)" }) -join "`n"
    Show-Message $text 'Histórico de execuções'
})
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
$ChooseDownloadDestinationButton.Add_Click({$selected=Select-Folder 'Escolha onde as tracks baixadas serão salvas' (Get-ODTDownloadPath);if($selected){if(-not$script:Settings.Acquisition.PSObject.Properties['DownloadPath']){$script:Settings.Acquisition|Add-Member NoteProperty DownloadPath $selected}else{$script:Settings.Acquisition.DownloadPath=$selected};Save-Settings;$DownloadDestinationText.Text=$selected;Update-ContextInformation}})
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
$ChooseRekordboxExeButton.Add_Click({Select-RekordboxExecutable})
$SendRekordboxCheck.Add_Click({$OrganizerPlaylistNameText.IsEnabled=[bool]$SendRekordboxCheck.IsChecked})
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
                # No Windows PowerShell 5.1, @($null).Count pode disparar
                # PropertyNotFoundException dentro de um evento do Dispatcher.
                # Measure-Object mantém o mesmo resultado sem derrubar a fila
                # enquanto o processo ainda não terminou.
                $resolvedCount=($resolved|Measure-Object).Count
                if($resolvedCount -gt 0){$pendingItems=New-Object Collections.Generic.List[object];foreach($request in @($resolved)){$pendingItems.Add($request)};$item|Add-Member NoteProperty PendingItems $pendingItems -Force;$item.Status='Expandindo';$item.ProgressValue=100;$item.Progress='100%';$item.Detail='Adicionando tracks ao grid'}
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
                }else{$item.Status='Expandida';$item.Detail='Tracks adicionadas ao grid';$resolvedContainers.Add($item)}
            }
            elseif($item.Kind -eq 'Download' -and $item.Status -eq 'Baixando'){try{[void](Get-ODTDownloadProgress -Download $item)}catch{$item.Status='Falhou';$item.Detail="Falha ao atualizar: $($_.Exception.Message)";Write-AppLog -Message $_.Exception.ToString() -Level ERROR}}
        }
        # Resolver e download são independentes do Rekordbox. A auditoria fará a
        # conferência de duplicatas/presença depois, sem bloquear esta fila.
        foreach($request in $newRequests){if($script:DownloadStartRequested -and $request.IsSelected){$request.Status='Pendente';$request.Progress='0%';$request.ProgressValue=0;$request.Detail='Aguardando vaga para baixar'};$script:DownloadQueue.Add($request)}
        foreach($container in $resolvedContainers){[void]$script:DownloadQueue.Remove($container)}
        $activeDownloads=@($script:DownloadQueue|Where-Object{$_.Status -eq 'Baixando'}).Count
        $engine=Get-ODTDownloaderPath;$ffmpeg=Get-ODTFFmpegPath
        for($i=0;$i -lt$script:DownloadQueue.Count -and $activeDownloads -lt 2;$i++){
            $request=$script:DownloadQueue[$i];if($request.Status -eq 'Pendente' -and -not$request.IsSelected){$request.Status='Pronto';$request.Progress='';$request.Detail='Desmarcada — clique em Iniciar download quando quiser';continue};if($request.Status -ne 'Pendente'){continue}
            try{$initialSource=if($request.PSObject.Properties['Artist'] -and $request.Artist){[string]$request.Artist}else{[string]$request.Source};$provider=if($request.PSObject.Properties['Artist']){[string]$request.Source}else{''};$thumbnail=if($request.PSObject.Properties['Thumbnail']){[string]$request.Thumbnail}else{''};$started=Start-ODTDownload -Url $request.DownloadUrl -DisplayUrl $request.Url -InitialTitle $request.Title -InitialSource $initialSource -Provider $provider -InitialDuration $request.Duration -InitialThumbnail $thumbnail -OutputRoot $request.OutputFolder -EnginePath $engine -FFmpegPath $ffmpeg -Quality '320';$started.IsSelected=$true;$script:DownloadQueue[$i]=$started;$activeDownloads++}catch{$request.Status='Falhou';$request.Detail=$_.Exception.Message;Write-AppLog -Message $_.Exception.ToString() -Level ERROR}
        }
        $active=@($script:DownloadQueue|Where-Object{$_.Status -in @('Baixando','Analisando','Expandindo','Pendente')}).Count;$done=@($script:DownloadQueue|Where-Object{$_.Status -eq 'Concluido'}).Count;$failed=@($script:DownloadQueue|Where-Object{$_.Status -in @('Falhou','Link privado')}).Count
        $DownloadQueueGrid.Items.Refresh();$DownloadStatusText.Text="$active em andamento | $done concluído(s) | $failed falha(s)";if($MainTabs.SelectedIndex -eq 0){$StatusText.Text="BAIXAR • $active EM ANDAMENTO • $done CONCLUÍDA(S) • $failed FALHA(S)"};if($active -eq 0 -and -not @($script:DownloadQueue|Where-Object{$_.Status -in @('Analisando','Expandindo','Pendente')}).Count){$script:DownloadStartRequested=$false;$script:DownloadTimer.Stop();Update-ContextInformation}
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
$WatchFolderCheck.IsChecked=if($script:Settings.PSObject.Properties['WatchFolderEnabled']){[bool]$script:Settings.WatchFolderEnabled}else{$false}
$configuredRekordbox='';if($script:Settings.PSObject.Properties['Rekordbox'] -and $script:Settings.Rekordbox.PSObject.Properties['ExecutablePath']){$configuredRekordbox=[Environment]::ExpandEnvironmentVariables([string]$script:Settings.Rekordbox.ExecutablePath)};$RekordboxExeText.Text=if($configuredRekordbox){$configuredRekordbox}else{'Localizar automaticamente'}
try{$RekordboxXmlText.Text=Get-RekordboxDatabasePath;$RekordboxSummaryText.Text='Base do Rekordbox detectada. Clique em Escanear biblioteca.'}catch{$RekordboxXmlText.Text='master.db não localizado — clique em Escolher outra'}
try{$removable=@(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=2' -ErrorAction Stop|Where-Object{$_.DeviceID}|Select-Object -First 1);if($removable.Count){$AuditUsbPathText.Text=[string]$removable[0].DeviceID+'\'}}catch{}
Refresh-UndoState
Update-ODTEnvironmentStatus|Out-Null
if ($ValidateOnly) {
    if (-not $window.Icon) { throw 'O ícone próprio do CRIVO DJ não foi carregado na janela.' }
    $tabOrder=@($MainTabs.Items|ForEach-Object{[string]$_.Header}) -join '|';if($tabOrder -ne 'BAIXAR|ORGANIZAR|AUDITORIA'){throw "Ordem de abas inválida: $tabOrder"}
    if(-not$SourceText -or -not$SendRekordboxCheck -or -not$OrganizerPlaylistNameText -or -not$EditTrackMetadataButton -or -not$AuditLibraryModeButton -or -not$AuditUsbModeButton -or -not$AuditUsbPathText -or -not$AuditFilterCombo -or -not$EditAuditMetadataButton -or -not$ReviewAuditButton -or -not$AuditDuplicateCount -or -not$SystemCheckButton -or -not$ExportDiagnosticButton -or -not$EnvironmentStatusText){throw 'Controles do fluxo Baixar > Organizar > Auditoria não foram carregados.'}
    if($window.Title -ne 'CRIVO DJ por MANEL Z0RD'){throw 'O título compacto da janela não foi aplicado.'}
    $auditHeaders=@($RekordboxAuditGrid.Columns|ForEach-Object{[string]$_.Header});foreach($header in @('ÁLBUM','GÊNERO','ANO','BPM','TONALIDADE','FORMATO','BITRATE','SAMPLE RATE','PLAYLIST(S)','ANÁLISE','PROBLEMA','DUPLICIDADE','PASTA ORIGEM','NÍVEL','DIAGNÓSTICO','LOCAL')){if($auditHeaders -notcontains $header){throw "A coluna de auditoria '$header' não foi carregada."}}
    $ModeGenreBpm.IsChecked=$true; Sync-FolderPattern
    if ($FolderPatternText.Text -ne '{GENERO} - {BPM_RANGE}') { throw 'O modelo de pasta não acompanhou o critério Gênero + BPM.' }
    $CustomizeFolderCheck.IsChecked=$true; Sync-FolderPattern; $FolderPatternText.Text='{GENERO}'
    if (-not (Get-TemplateCriteriaError -Template $FolderPatternText.Text)) { throw 'A personalização permitiu remover um critério obrigatório.' }
    $FolderPatternText.Text='Estilo - {GENERO}\Faixa - {BPM_RANGE}'
    if (Get-TemplateCriteriaError -Template $FolderPatternText.Text) { throw 'Um modelo personalizado válido foi recusado.' }
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
    foreach($context in @(@(0,'BAIXAR'),@(1,'ORGANIZAR'),@(2,'AUDITORIA'))){$MainTabs.SelectedIndex=[int]$context[0];Update-ContextInformation;if(-not$StatusText.Text.StartsWith([string]$context[1])){throw "O rodapé não acompanhou a aba $($context[1])."}}
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
$window.ShowDialog() | Out-Null
