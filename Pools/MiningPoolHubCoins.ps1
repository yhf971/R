﻿using module ..\Include.psm1

param(
    [PSCustomObject]$Wallets,
    [PSCustomObject]$Params,
    [alias("WorkerName")]
    [String]$Worker,
    [alias("UserName")]
    [String]$User,
    [TimeSpan]$StatSpan,
    [Bool]$AllowZero = $false,
    [String]$StatAverage = "Minute_10",
    [String]$AEcurrency = ""
)

$Name = Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName

$Pool_Request = [PSCustomObject]@{}

try {
    $Pool_Request = Invoke-RestMethodAsync "https://miningpoolhub.com/index.php?page=api&action=getminingandprofitsstatistics&{timestamp}" -tag $Name -cycletime 120
}
catch {
    if ($Error.Count){$Error.RemoveAt(0)}
    Write-Log -Level Warn "Pool API ($Name) has failed. "
    return
}

if (($Pool_Request.return | Measure-Object).Count -le 1) {
    Write-Log -Level Warn "Pool API ($Name) returned nothing. "
    return
}

[hashtable]$Pool_Algorithms = @{}
[hashtable]$Pool_RegionsTable = @{}

$Pool_Regions = @("europe", "us-east", "asia")
$Pool_Regions | Foreach-Object {$Pool_RegionsTable.$_ = Get-Region $_}

$Pool_Fee = 0.9 + 0.2

$Pool_Currency = if ($AEcurrency) {$AEcurrency} else {"BTC"}

$Pool_Request.return | ForEach-Object {
    $Pool_Host      = $_.host
    $Pool_Hosts     = $_.host_list.split(";")
    $Pool_Port      = $_.port
    $Pool_Algorithm = $_.algo
    if (-not $Pool_Algorithms.ContainsKey($Pool_Algorithm)) {$Pool_Algorithms.$Pool_Algorithm = Get-Algorithm $Pool_Algorithm}
    $Pool_Algorithm_Norm = $Pool_Algorithms.$Pool_Algorithm
    $Pool_Coin   = $_.coin_name
    $Pool_Symbol = $_.symbol
    if (-not $Pool_Symbol) {
        $Pool_Symbol = Get-CoinSymbol $_.coin_name
        if (-not $Pool_Symbol -and $_.coin_name -match '-') {
            $Pool_Symbol = Get-CoinSymbol ($_.coin_name -split '-' | Select-Object -Index 0)
        }
    }

    if ($Pool_Algorithm_Norm -eq "Sia") {$Pool_Algorithm_Norm = "SiaClaymore"} #temp fix

    $Divisor = 1e9

    $Pool_TSL = if ($_.time_since_last_block -eq "-") {$null} else {[int64]$_.time_since_last_block}

    if (-not $InfoOnly) {
        $Stat = Set-Stat -Name "$($Name)_$($Pool_Coin)_Profit" -Value ([Double]$_.profit / $Divisor) -Duration $StatSpan -ChangeDetection $true -HashRate (ConvertFrom-Hash $_.pool_hash) -FaultDetection $true -FaultTolerance 5 -Quiet
        if (-not $Stat.HashRate_Live -and -not $AllowZero) {return}
    }

    foreach($Pool_Region in $Pool_Regions) {
        if ($User -or $InfoOnly) {
            [PSCustomObject]@{
                Algorithm     = $Pool_Algorithm_Norm
				Algorithm0    = $Pool_Algorithm_Norm
                CoinName      = $Pool_Coin
                CoinSymbol    = $Pool_Symbol
                Currency      = $Pool_Currency
                Price         = $Stat.$StatAverage #instead of .Live
                StablePrice   = $Stat.Week
                MarginOfError = $Stat.Week_Fluctuation
                Protocol      = "stratum+tcp"
                Host          = $Pool_Hosts | Sort-Object -Descending {$_ -ilike "$Pool_Region*"} | Select-Object -First 1
                Port          = $Pool_Port
                User          = "$User.{workername:$Worker}"
                Pass          = "x{diff:,d=`$difficulty}"
                Region        = $Pool_RegionsTable.$Pool_Region
                SSL           = $false
                Updated       = $Stat.Updated
                PoolFee       = $Pool_Fee
                Hashrate      = $Stat.HashRate_Live
                TSL           = $Pool_TSL
                EthMode       = if ($Pool_Algorithm_Norm -match "^(Ethash|ProgPow)") {"ethstratumnh"} else {$null}
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

            if ($Pool_Algorithm_Norm -like "Cryptonight*" -or $Pool_Algorithm_Norm -like "Equihash*") {
                [PSCustomObject]@{
                    Algorithm     = $Pool_Algorithm_Norm
					Algorithm0    = $Pool_Algorithm_Norm
                    CoinName      = $Pool_Coin
                    CoinSymbol    = $Pool_Symbol
                    Currency      = $Pool_Currency
                    Price         = $Stat.$StatAverage #instead of .Live
                    StablePrice   = $Stat.Week
                    MarginOfError = $Stat.Week_Fluctuation
                    Protocol      = "stratum+ssl"
                    Host          = $Pool_Hosts | Sort-Object -Descending {$_ -ilike "$Pool_Region*"} | Select-Object -First 1
                    Port          = $Pool_Port
                    User          = "$User.{workername:$Worker}"
                    Pass          = "x{diff:,d=`$difficulty}"
                    Region        = $Pool_RegionsTable.$Pool_Region
                    SSL           = $true
                    Updated       = $Stat.Updated                        
                    PoolFee       = $Pool_Fee
                    Hashrate      = $Stat.HashRate_Live
                    TSL           = $Pool_TSL
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
            }
        }
    }
}