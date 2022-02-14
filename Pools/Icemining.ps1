﻿using module ..\Modules\Include.psm1

param(
    [PSCustomObject]$Wallets,
    [PSCustomObject]$Params,
    [alias("WorkerName")]
    [String]$Worker,
    [TimeSpan]$StatSpan,
    [String]$DataWindow = "estimate_current",
    [Bool]$InfoOnly = $false,
    [Bool]$AllowZero = $false,
    [String]$StatAverage = "Minute_10",
    [String]$StatAverageStable = "Week"
)

$Name = Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName

$Pool_Fee = 1

$Pool_Request = [PSCustomObject]@{}
$PoolCoins_Request = [PSCustomObject]@{}

try {
    $PoolCoins_Request = Invoke-RestMethodAsync "https://icemining.ca/api/currencies" -tag $Name -cycletime 120
    if ($PoolCoins_Request -is [string]) {$PoolCoins_Request = ($PoolCoins_Request -replace '<script.+?/script>' -replace '<.+?>').Trim() | ConvertFrom-Json -ErrorAction Stop}
}
catch {
    if ($Error.Count){$Error.RemoveAt(0)}
    Write-Log -Level Warn "Pool API ($Name) has failed. "
    return
}

if (($PoolCoins_Request | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Measure-Object Name).Count -le 1) {
    Write-Log -Level Warn "Pool API ($Name) returned nothing. "
    return
}

[hashtable]$Pool_RegionsTable = @{}

$Pool_Regions = @("us","eu","asia")
$Pool_Regions | Foreach-Object {$Pool_RegionsTable.$_ = Get-Region $_}

$Pools_Data = @(
    #[PSCustomObject]@{symbol="EPIC-Cuckatoo31"; region = @("us"); host=@("epic.hashrate.to"); port=4000; fee = 2}
    [PSCustomObject]@{symbol="EPIC-RandomEPIC"; region = @("us"); host=@("epic.hashrate.to"); port=4000; fee = 2; hashrate = "randomx"}
    [PSCustomObject]@{symbol="EPIC-ProgPoW";    region = @("us"); host=@("epic.hashrate.to"); port=4000; fee = 2; hashrate = "progpow"}
    [PSCustomObject]@{symbol="NIM";             region = @("us"); host=@("nimiq.icemining.ca"); port=2053; fee = 1.25; ssl = $true}
    #[PSCustomObject]@{symbol="SIN";             region = @("us","eu","asia"); host=@("stratum.icemining.ca","eu.icemining.ca","asia.icemining.ca"); port=4205; fee = 1}
    [PSCustomObject]@{symbol="TON";             region = @("us"); host=@("ton.hashrate.to"); port=4003; fee = 1}
)

$Pools_Data | Where-Object {$Pool_Currency = $_.symbol -replace "-.+$"; $PoolCoins_Request.$Pool_Currency -ne $null -and ($Wallets.$Pool_Currency -or $InfoOnly)} | ForEach-Object {
    $Pool_Coin           = Get-Coin $_.symbol

    if ($Pool_Coin) {
        $Pool_Algorithm  = $Pool_Coin.Algo
        $Pool_CoinName   = $Pool_Coin.Name
    } else {
        $Pool_Algorithm  = $PoolCoins_Request.$Pool_Currency.algo
        $Pool_CoinName   = $PoolCoins_Request.$Pool_Currency.name
    }

    $Pool_Algorithm_Norm = Get-Algorithm $Pool_Algorithm

    if (-not $InfoOnly) {
        $Stat = Set-Stat -Name "$($Name)_$($_.symbol)_Profit" -Value 0 -Duration $StatSpan -ChangeDetection $false -HashRate $(if ($_.hashrate) {$PoolCoins_Request.$Pool_Currency.hashrate."$($_.hashrate)"} elseif ($Pool_Currency -eq "EPIC") {10} else {$PoolCoins_Request.$Pool_Currency.hashrate}) -BlockRate $PoolCoins_Request.$Pool_Currency."24h_blocks" -Quiet
        if (-not $Stat.HashRate_Live -and -not $AllowZero) {return}
    }

    $Pool_User = "$($Wallets.$Pool_Currency).{workername:$Worker}"
    $Pool_Protocol = "$(if ($Pool_Currency -ne "TON") {"stratum+$(if ($_.ssl) {"ssl"} else {"tcp"})"})"
    $Pool_Fee = if ($PoolCoins_Request.$Pool_Currency.reward_model.PPLNS -ne $null) {[double]$PoolCoins_Request.$Pool_Currency.reward_model.PPLNS} else {$_.fee}

    $Pool_Pass = if ($Pool_Currency -eq "SIN") {
        "c=$Pool_Currency{diff:,d=`$difficulty}$(if ($Params.$Pool_Currency) {",$($Params.$Pool_Currency)"})"
    } else {
        "$(if ($Params.$Pool_Currency) {$Params.$Pool_Currency} else {"x"})"
    }

    $i = 0
    foreach($Pool_Region in $_.region) {
        [PSCustomObject]@{
            Algorithm     = $Pool_Algorithm_Norm
			Algorithm0    = $Pool_Algorithm_Norm
            CoinName      = $Pool_CoinName
            CoinSymbol    = $Pool_Currency
            Currency      = $Pool_Currency
            Price         = 0
            StablePrice   = 0
            MarginOfError = 0
            Protocol      = $Pool_Protocol
            Host          = "$($_.host[$i])"
            Port          = $_.port
            User          = $Pool_User
            Pass          = $Pool_Pass
            Region        = $Pool_RegionsTable.$Pool_Region
            SSL           = if ($_.ssl) {$true} else {$false}
            Updated       = $Stat.Updated
            PoolFee       = $Pool_Fee
            Workers       = $PoolCoins_Request.$Pool_Currency.workers
            Hashrate      = $Stat.HashRate_Live
            BLK           = $Stat.BlockRate_Average
            TSL           = $PoolCoins_Request.$Pool_Currency.timesincelast
            WTM           = $true
            Name          = $Name
            Penalty       = 0
            PenaltyFactor = 1
            Disabled      = $false
            HasMinerExclusions = $false
            Price_Bias    = 0.0
            Price_Unbias  = 0.0
            Wallet        = $Wallets.$Pool_Currency
            Worker        = "{workername:$Worker}"
            Email         = $Email
        }
        $i++
    }
}
