[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$skillRoot = Split-Path -Parent $PSScriptRoot
$skillPath = Join-Path $skillRoot 'SKILL.md'
$failures = [System.Collections.Generic.List[string]]::new()
$passes = 0

function Add-Result {
    param(
        [string]$Name,
        [bool]$Passed,
        [string]$Failure
    )

    if ($Passed) {
        $script:passes++
        Write-Host "PASS: $Name"
        return
    }

    $script:failures.Add("$Name — $Failure")
    Write-Host "FAIL: $Name — $Failure"
}

function Get-LineNumber {
    param(
        [string]$Text,
        [string]$Pattern
    )

    $match = [regex]::Match($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) {
        return $null
    }

    return ($Text.Substring(0, $match.Index) -split "\r?\n").Count
}

function Assert-Regex {
    param(
        [string]$Name,
        [string]$Text,
        [string]$Pattern,
        [string]$Expectation
    )

    Add-Result -Name $Name -Passed ([regex]::IsMatch(
            $Text,
            $Pattern,
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
            [System.Text.RegularExpressions.RegexOptions]::Singleline -bor
            [System.Text.RegularExpressions.RegexOptions]::Multiline
        )) -Failure "missing $Expectation"
}

function Assert-Literal {
    param(
        [string]$Name,
        [string]$Text,
        [string]$Literal
    )

    Add-Result -Name $Name -Passed $Text.Contains($Literal) -Failure "missing literal '$Literal'"
}

function Assert-NotRegex {
    param(
        [string]$Name,
        [string]$Text,
        [string]$Pattern,
        [string]$Description
    )

    $match = [regex]::Match(
        $Text,
        $Pattern,
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
    $line = if ($match.Success) { Get-LineNumber -Text $Text -Pattern $Pattern } else { $null }
    $failure = if ($match.Success) {
        "forbidden $Description found on line ${line}: '$($match.Value -replace '\s+', ' ')'"
    }
    else {
        "forbidden $Description is present"
    }

    Add-Result -Name $Name -Passed (-not $match.Success) -Failure $failure
}

function Assert-PatternOrder {
    param(
        [string]$Name,
        [string]$Text,
        [string[]]$Patterns,
        [string]$Expectation
    )

    $options = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    $patternMatches = @($Patterns | ForEach-Object { [regex]::Match($Text, $_, $options) })
    $missingIndex = [Array]::FindIndex(
        [System.Text.RegularExpressions.Match[]]$patternMatches,
        [Predicate[System.Text.RegularExpressions.Match]] { param($match) -not $match.Success }
    )
    $isOrdered = $missingIndex -eq -1

    if ($isOrdered) {
        for ($index = 1; $index -lt $patternMatches.Count; $index++) {
            if ($patternMatches[$index - 1].Index -ge $patternMatches[$index].Index) {
                $isOrdered = $false
                break
            }
        }
    }

    $failure = if ($missingIndex -ge 0) {
        "missing ordered step $($missingIndex + 1): $Expectation"
    }
    else {
        "out-of-order steps: $Expectation"
    }

    Add-Result -Name $Name -Passed $isOrdered -Failure $failure
}

if (-not (Test-Path -LiteralPath $skillPath -PathType Leaf)) {
    Write-Host "FAIL: SKILL.md was not found at $skillPath"
    exit 1
}

$content = [System.IO.File]::ReadAllText($skillPath)
$phase4 = [regex]::Match($content, '(?ms)^### Phase 4.*?(?=^### Phase 5)').Value
$phase5 = [regex]::Match($content, '(?ms)^### Phase 5.*?(?=^### Phase 6)').Value
$scheduleContract = [regex]::Match($content, '(?ms)^### Schedule ownership contract.*?(?=^## Response-handling rules)').Value

Assert-Regex -Name 'Frontmatter is present' -Text $content -Pattern '\A---\s*\r?\n.*?\r?\n---' -Expectation 'YAML frontmatter'
Assert-Regex -Name 'Frontmatter names this skill' -Text $content -Pattern '\A---\s*\r?\n.*?^name:\s*enable-progress-in-teams\s*$' -Expectation 'name: enable-progress-in-teams'
Assert-Regex -Name 'Frontmatter describes selectable destination' -Text $content -Pattern '\A---\s*\r?\n.*?^description:.*?(?:operator-selected|chosen\s+interactively|selected\s+.*destination|change\s+the\s+Teams\s+progress\s+target)' -Expectation 'a dynamic/selectable destination description'
Assert-Regex -Name 'Frontmatter keeps version 1.2.0' -Text $content -Pattern '\A---\s*\r?\n.*?^metadata:\s*\r?\n\s+version:\s*["'']1\.2\.0["'']\s*$' -Expectation 'metadata.version 1.2.0'

foreach ($literal in @(
        'ListTeams',
        'ListChannels',
        'slug',
        'team_id',
        'channel_id',
        'confirmation gate',
        'route_generation',
        'Route generation:',
        'Change target',
        'Status',
        'Disable',
        'terminal cleanup',
        'logical_schedule_key',
        'schedule_id',
        'lease_owner',
        'watermark',
        'reply_ledger',
        'listening_degraded',
        'authorization_revision',
        'teams_progress_authorization',
        '6e507591-b016-4741-8543-11b3e2ff8e29'
    )) {
    Assert-Literal -Name "Required term: $literal" -Text $content -Literal $literal
}

Assert-Regex -Name 'Slug is opaque and non-canonical' -Text $content -Pattern 'slug.*opaque.*(?:not an identity|never an identity)' -Expectation 'opaque session slug semantics'
Assert-Regex -Name 'Canonical IDs are required for routing' -Text $content -Pattern 'Canonical IDs are the only routing identity' -Expectation 'canonical team_id/channel_id routing rule'
Assert-Regex -Name 'Root marker is generation specific' -Text $content -Pattern 'Session ID:\s*<SESSION_ID>.*?Route generation:\s*<GENERATION>' -Expectation 'two-line session and route-generation root marker'
Assert-Regex -Name 'Retarget requires a new generation' -Text $content -Pattern '(?:Change target|Retarget).*?(?:new generation|next monotonic generation|generation-specific root)' -Expectation 'generation-safe retarget'

Assert-Regex -Name 'One unified schedule owns polling and reconciliation' -Text $content -Pattern 'exactly one logical recurring schedule.*?runs every 5 minutes and owns both routing\s+reconciliation and reply polling' -Expectation 'one unified 5-minute schedule'
Assert-Regex -Name 'Cadence cost and latency are disclosed' -Text $content -Pattern '(?:about|~)\s*288 ticks/day.*?(?:about|~)\s*5 minutes|(?:about|~)\s*5 minutes.*?(?:about|~)\s*288 ticks/day' -Expectation 'about 288 ticks/day and about 5 minutes'
Assert-NotRegex -Name 'No contradictory two-minute cadence' -Text $content -Pattern '\b2[- ]minute(?:s)?\b|\bevery\s+2\s+minutes\b' -Description '2-minute cadence'
Assert-NotRegex -Name 'No contradictory ten-minute cadence' -Text $content -Pattern '\b10[- ]minute(?:s)?\b|\bevery\s+10\s+minutes\b' -Description '10-minute cadence'

Assert-Regex -Name 'Authorization is separate and sender-ID-only' -Text $content -Pattern 'Separate, id-only authorization.*?sender \*\*id\*\* is in `authorized_sender_ids`' -Expectation 'separate sender-ID authorization'
Assert-Regex -Name 'Authorization requires leading ToAgent prefix' -Text $content -Pattern 'starts exactly with\s*`\[ToAgent\]`' -Expectation 'leading [ToAgent] authorization prefix'
Assert-Regex -Name 'Authorization rejects display-name and membership authorization' -Text $content -Pattern 'Never accept by `displayName`.*?display name is diagnostics only' -Expectation 'no display-name authorization'
Assert-Regex -Name 'Authorization remains untouched by retarget' -Text $content -Pattern 'retarget NEVER writes this table|retarget never writes' -Expectation 'retarget isolation from authorization'

Assert-Regex -Name 'Persistent state has schedule identity and lease' -Text $content -Pattern 'logical_schedule_key.*?schedule_id.*?lease_owner' -Expectation 'schedule logical key, handle, and lease state'
Assert-Regex -Name 'Persistent state has monotonic generation and root' -Text $content -Pattern 'route_generation.*?root_message_id.*?monotonic' -Expectation 'monotonic generation and root state'
Assert-Regex -Name 'Persistent state has cursor and ledger' -Text $content -Pattern 'watermark_created_at.*?watermark_message_id.*?teams_progress_reply_ledger' -Expectation 'watermark/cursor and reply ledger'
Assert-Regex -Name 'Persistent state has degraded and authorization state' -Text $content -Pattern 'backlog_state.*?listening_degraded.*?teams_progress_authorization.*?authorization_revision' -Expectation 'degraded backlog and separate authorization revision state'

Assert-Regex -Name 'Ticks reload state and guard ownership' -Text $content -Pattern 'Reload and guard.*?Verify ownership before every external effect.*?route_generation.*?logical_schedule_key.*?lease' -Expectation 'tick reload and generation/key/lease guards'
Assert-Regex -Name 'Reply polling uses bounded pagination' -Text $content -Pattern 'following `nextLink` up to a bounded \*\*5 pages\*\* per\s+tick' -Expectation 'bounded reply pagination'
Assert-Regex -Name 'Exhausted pagination retains watermark and degrades after three ticks' -Text $content -Pattern 'pagination exhaustion.*?retain the prior watermark.*?After \*\*3 consecutive\*\*.*?listening_degraded' -Expectation 'no watermark advance and threshold 3 degradation'
Assert-Regex -Name 'Ledger is written before surfacing' -Text $content -Pattern 'Ledger before surface.*?Insert a `reply_ledger` row.*?before surfacing' -Expectation 'ledger-before-surface behavior'
Assert-Regex -Name 'Accepted replies queue at a safe local approval point' -Text $content -Pattern 'queued for the next safe local approval point' -Expectation 'safe local approval queue'
Assert-Regex -Name 'Polling makes no preemption or webhook guarantee' -Text $content -Pattern 'not a webhook.*?guaranteed interrupt|cannot claim preemptive interruption' -Expectation 'no guaranteed preemption/webhook language'

Assert-Regex -Name 'Blocked flow reuses the unified timer' -Text $content -Pattern 'Blocked:.*?no separate schedule.*?existing one 5-minute session schedule.*?both active and blocked states' -Expectation 'blocked flow reuse of the unified timer'
Assert-NotRegex -Name 'Blocked flow does not create a schedule only when blocked' -Text $content -Pattern '(?:create\s+(?:a|the|any)\s+(?:separate\s+)?schedule\s+only\s+when\s+blocked|only\s+when\s+blocked.{0,100}create\s+(?:a|the|any)\s+schedule)' -Description 'blocked-only schedule instruction'

Assert-Regex -Name 'SV-01: Watermark schema retains both tuple columns' -Text $content -Pattern 'watermark_created_at\s+TEXT.*?watermark_message_id\s+TEXT' -Expectation 'both durable watermark columns'
Assert-Regex -Name 'SV-01: Watermark qualification is lexicographic' -Text $content -Pattern 'createdDateTime > watermark_created_at OR \(createdDateTime = watermark_created_at AND message_id > watermark_message_id\)' -Expectation 'the exact composite watermark disjunction'
Assert-Regex -Name 'SV-01: Watermark tie-break is stable ordinal' -Text $phase4 -Pattern 'stable ordinal id tie-break' -Expectation 'a stable ordinal ID tie-break in Phase 4'
Assert-Regex -Name 'SV-01: Watermark sorting and qualification use the same tuple' -Text $phase4 -Pattern 'Sort.*?\(createdDateTime, message_id\).*?composite rule.*?createdDateTime > watermark_created_at OR \(createdDateTime = watermark_created_at AND message_id > watermark_message_id\)' -Expectation 'sorting and qualification on the same tuple'
Assert-Regex -Name 'SV-01: Watermark advances only to greatest fully processed tuple' -Text $phase4 -Pattern 'greatest fully processed `\(createdDateTime, message_id\)`.*?pagination exhaustion.*?retain the prior watermark tuple' -Expectation 'greatest-fully-processed advancement and exhaustion retention'
Assert-NotRegex -Name 'SV-01: Timestamp-only cursor qualification is absent' -Text $content -Pattern 'createdDateTime\s*>\s*watermark_created_at(?!\s+OR\s+\()' -Description 'timestamp-only watermark qualification without the message ID override'

Assert-Regex -Name 'SV-02: Schedule revision and intent token are persisted' -Text $content -Pattern 'schedule_revision\s+INTEGER.*?schedule_intent_token\s+TEXT' -Expectation 'schedule revision and intent-token state columns'
Assert-Regex -Name 'SV-02: Schedule CAS uses all five dimensions' -Text $scheduleContract -Pattern '`\(session_id, logical_schedule_key, expected_schedule_revision, schedule_intent_token, route_generation\)`' -Expectation 'the five-dimensional schedule adoption CAS tuple'
Assert-PatternOrder -Name 'SV-02: Schedule create and adoption use ordered CAS lifecycle' -Text $scheduleContract -Patterns @(
    'Capture \+ intent',
    'BEFORE calling\s+`manage_schedule` create',
    'Adopt only by CAS',
    'increment `schedule_revision`',
    'LOSER: stop the just-created external schedule and reconcile'
) -Expectation 'capture intent before create, CAS adoption then revision increment, and loser stop/reconciliation'
Assert-Regex -Name 'SV-02: Schedule revision has a zero baseline' -Text $content -Pattern 'schedule_revision = 0.*?baseline' -Expectation 'baseline schedule revision zero'
Assert-Regex -Name 'SV-02: Stale intents and uncertain stop outcomes remain visible' -Text $scheduleContract -Pattern '(?:Stale intent tokens.*?uncertain stop outcomes|unconsumed `schedule_intent_token`s).*?(?:remain visible|Visibly retain).*?(?:reconciliation|never hide)' -Expectation 'visible stale/unknown schedule outcomes'

Assert-Regex -Name 'SV-03: Tick captures authorization revision and sender snapshot' -Text $phase4 -Pattern 'separate `teams_progress_authorization`.*?capturing this tick''s initial `authorization_revision` and `authorized_sender_ids`' -Expectation 'captured authorization revision and sender snapshot'
Assert-Regex -Name 'SV-03: Every external effect revalidates authorization revision' -Text $phase4 -Pattern 'Before each external read or write.*?current `authorization_revision`.*?changed\s+`authorization_revision`.*?no Teams read/write' -Expectation 'per-effect authorization revision guard'
Assert-Regex -Name 'SV-03: Claim and surface require current authorization' -Text $phase4 -Pattern 'Ledger before surface.*?reload.*?authorization.*?sender id.*?authorized.*?On any mismatch.*?leave it unclaimed.*?do not ledger' -Expectation 'claim/surface revalidation that leaves stale replies unclaimed'
Assert-Regex -Name 'SV-03: Acknowledgement never uses stale authorization' -Text $phase4 -Pattern 'Before writing any acknowledgement.*?same captured `authorization_revision`.*?never acknowledge under a stale or changed authorization revision' -Expectation 'acknowledgement revalidation and stale-authorization rejection'

Assert-Regex -Name 'SV-04: Transition key includes session and both generations' -Text $content -Pattern 'PRIMARY KEY \(session_id, from_generation, to_generation\)' -Expectation 'three-part retarget transition primary key'
Assert-PatternOrder -Name 'SV-04: Retarget orders allocation, keyed transition, root, activation, and handoff' -Text $phase5 -Patterns @(
    'allocate the next monotonic `route_generation` FIRST',
    'persist a `teams_progress_transition` row keyed by\s+`\(session_id, from_generation, to_generation\)` in state `new_root_pending`',
    'create/bind the new generation-specific root',
    'atomically CAS-commit the new current generation',
    'post at most ONE guarded handoff reply'
) -Expectation 'allocation, new_root_pending transition, root binding, atomic activation, then old-root handoff within Phase 5'
Assert-Regex -Name 'SV-04: Transition persists before the first new-channel write' -Text $phase5 -Pattern 'route_generation` FIRST.*?before any\s+write to the new channel.*?new_root_pending' -Expectation 'generation allocation and transition persistence before new-channel writing'
Assert-Regex -Name 'SV-04: Retarget failure preserves the old current route' -Text $phase5 -Pattern 'failure before durable root binding.*?retain the old route as current.*?do NOT update the\s+slug/current route.*?`failed`/`degraded`' -Expectation 'old-route preservation and failed/degraded transition evidence'
Assert-NotRegex -Name 'SV-04: Transition is never written before generation allocation' -Text $content -Pattern 'Write a `teams_progress_transition` row.*?BEFORE any.*?write.*?Allocate the next monotonic generation' -Description 'pre-remediation transition-before-allocation ordering'

foreach ($requirement in @(
        @{ Name = 'Stale or deleted target failure is defined'; Pattern = 'Stale/deleted/inaccessible target' },
        @{ Name = 'Scheduler unavailable failure is defined'; Pattern = 'Scheduler unavailable' },
        @{ Name = 'Schedule persistence failure is defined'; Pattern = 'Schedule persistence failure after create' },
        @{ Name = 'Concurrent schedules are reconciled'; Pattern = 'Duplicate schedule creation' },
        @{ Name = 'Pagination exhaustion failure is defined'; Pattern = 'pagination exhausted' },
        @{ Name = 'Acknowledgement ambiguity is defined'; Pattern = 'Acknowledgement ambiguous' },
        @{ Name = 'Stop failure is defined'; Pattern = 'Stop failure' },
        @{ Name = 'Disable flow is defined'; Pattern = 'Disable.*?first-class trusted local control' },
        @{ Name = 'Terminal cleanup is defined'; Pattern = 'Terminal cleanup' }
    )) {
    Assert-Regex -Name $requirement.Name -Text $content -Pattern $requirement.Pattern -Expectation $requirement.Name.ToLowerInvariant()
}

foreach ($forbidden in @(
        @{ Name = 'Old team ID is absent'; Pattern = 'cf0bc7fc-3957-47ab-a270-de8cab08cf98'; Description = 'old team ID' },
        @{ Name = 'Old channel ID is absent'; Pattern = '3uz38MVu2jWGdYNcs9OVJNCks4'; Description = 'old channel ID' },
        @{ Name = 'Single-permitted wording is absent'; Pattern = 'single permitted destination'; Description = 'single permitted destination wording' },
        @{ Name = 'Old listener table is absent'; Pattern = 'teams_progress_listener'; Description = 'old listener table' },
        @{ Name = 'Old listener key is absent'; Pattern = 'listener_key'; Description = 'old listener key' },
        @{ Name = 'Four-hour lifecycle is absent'; Pattern = '\b4[- ]hour\b'; Description = '4-hour lifecycle' },
        @{ Name = 'Two-minute cadence wording is absent'; Pattern = '\b2-minute cadence\b'; Description = '2-minute cadence wording' },
        @{ Name = 'Ten-minute cadence wording is absent'; Pattern = '\b10-minute cadence\b'; Description = '10-minute cadence wording' }
    )) {
    Assert-NotRegex -Name $forbidden.Name -Text $content -Pattern $forbidden.Pattern -Description $forbidden.Description
}

$completion = [regex]::Match($content, '(?ms)^## Completion\s*\r?\n(.*)\z')
if (-not $completion.Success) {
    Add-Result -Name 'Completion block is present' -Passed $false -Failure 'missing Completion section'
}
else {
    $fencedBlock = [regex]::Match($completion.Groups[1].Value, '(?s)```markdown\s*(.*?)```')
    if (-not $fencedBlock.Success) {
        Add-Result -Name 'Completion block is fenced' -Passed $false -Failure 'missing markdown completion template'
    }
    else {
        $bulletCount = ([regex]::Matches($fencedBlock.Groups[1].Value, '(?m)^\s*-\s+')).Count
        Add-Result -Name 'Completion has at most seven bullets' -Passed ($bulletCount -le 7) -Failure "completion template has $bulletCount bullets; expected at most 7"
        foreach ($field in @('Destination:', 'Slug / generation / root:', 'Timer:', 'Listening:', 'Degraded / local fallback:', 'Next action: <only for PARTIAL or BLOCKED>')) {
            Add-Result -Name "Completion includes $field" -Passed $fencedBlock.Groups[1].Value.Contains($field) -Failure "completion template is missing '$field'"
        }
    }
}

if ($failures.Count -gt 0) {
    Write-Host "`n$($failures.Count) contract assertion(s) failed:"
    $failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "`nPASS: $passes static skill contract assertions passed."
exit 0
