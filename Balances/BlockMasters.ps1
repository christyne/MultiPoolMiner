﻿using module ..\Include.psm1

param(
    [Parameter(Mandatory = $true)]
    [PSCustomObject]$Config
)

$Name = Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName
$PoolConfig = $Config.Pools.$Name

$RetryCount = 3
$RetryDelay = 2
while (-not ($APIRequest) -and $RetryCount -gt 0) {
    try {
        if (-not $APIRequest) {$APIRequest = Invoke-RestMethod "http://blockmasters.co/api/currencies" -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop}
    }
    catch {
        Start-Sleep -Seconds $RetryDelay # Pool might not like immediate requests
        $RetryCount--        
    }
}

if (-not $APIRequest) {
    Write-Log -Level Warn "Pool Balance API ($Name) has failed. "
    return
}

if (($APIRequest | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Measure-Object Name).Count -le 1) {
    Write-Log -Level Warn "Pool Balance API ($Name) returned nothing. "
    return
}

# Guaranteed payout currencies
$Payout_Currencies = @("BTC", "LTC", "DASH")
$Payout_Currencies = $Payout_Currencies + @($APIRequest | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name) | Select-Object -Unique | Sort-Object | Where-Object {$PoolConfig.$_}

if (-not $Payout_Currencies) {
    Write-Log -Level Verbose "Cannot get balance on pool ($Name) - no wallet address specified. "
    return
}

$Payout_Currencies | Foreach-Object {
    try {
        $APIRequest = Invoke-RestMethod "http://blockmasters.co/api/wallet?address=$($PoolConfig.$_)" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        [PSCustomObject]@{
            Name        = "$($Name) ($($APIRequest.currency))"
            Pool        = $Name
            Currency    = $APIRequest.currency
            Balance     = $APIRequest.balance
            Pending     = $APIRequest.unsold
            Total       = $APIRequest.unpaid
            LastUpdated = (Get-Date).ToUniversalTime()
        }
    }
    catch {
        Write-Log -Level Warn "Pool Balance API ($Name) has failed. "
    }

    if (($APIRequest | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Measure-Object Name).Count -le 1) {
        Write-Log -Level Warn "Pool Balance API ($Name) for $_ returned nothing. "
        return
    }
}
