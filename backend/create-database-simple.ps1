# Simple script to create Firebase Realtime Database using Firebase REST API
# No gcloud CLI needed - uses Firebase token directly

$PROJECT_ID = "canma-wallet"
$LOCATION = "asia-southeast1"

Write-Host "=== Creating Firebase Realtime Database ===" -ForegroundColor Cyan
Write-Host "Project: $PROJECT_ID" -ForegroundColor Yellow
Write-Host "Location: $LOCATION" -ForegroundColor Yellow
Write-Host ""

# Get Firebase token
Write-Host "Getting Firebase authentication token..." -ForegroundColor Yellow
$tokenOutput = firebase login:ci --no-localhost 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error getting token. Trying to use existing session..." -ForegroundColor Yellow
}

# Try to get token from firebase
$TOKEN = ""
try {
    # Use firebase CLI to get access token via debug mode
    $debugOutput = firebase database:get / --project $PROJECT_ID 2>&1
    Write-Host "Attempting to create database instance..." -ForegroundColor Yellow
} catch {
    Write-Host "Could not access database - it may not exist yet" -ForegroundColor Yellow
}

# Enable Firebase Database API first
Write-Host ""
Write-Host "Step 1: Enabling Firebase Database API..." -ForegroundColor Cyan

$enableApiUrl = "https://serviceusage.googleapis.com/v1/projects/canma-wallet/services/firebasedatabase.googleapis.com:enable"

# Try using firebase token for API calls
$firebaseToken = firebase login:ci --no-localhost 2>&1 | Select-String -Pattern "1//" | ForEach-Object { $_.ToString().Trim() }

if ($firebaseToken) {
    Write-Host "Using Firebase token for API calls..." -ForegroundColor Green
    
    # Create database instance
    Write-Host ""
    Write-Host "Step 2: Creating Realtime Database instance..." -ForegroundColor Cyan
    
    $createDbUrl = "https://firebasedatabase.googleapis.com/v1beta/projects/$PROJECT_ID/locations/$LOCATION/instances?databaseId=$PROJECT_ID-default-rtdb"
    
    $body = @{
        type = "USER_DATABASE"
    } | ConvertTo-Json
    
    try {
        $response = Invoke-RestMethod -Uri $createDbUrl -Method POST -Headers @{
            "Authorization" = "Bearer $firebaseToken"
            "Content-Type" = "application/json"
        } -Body $body
        
        Write-Host "✓ Database created successfully!" -ForegroundColor Green
        Write-Host ""
        Write-Host "Database URL: https://$PROJECT_ID-default-rtdb.asia-southeast1.firebasedatabase.app" -ForegroundColor Green
        
    } catch {
        $errorMessage = $_.Exception.Message
        if ($errorMessage -like "*already exists*") {
            Write-Host "✓ Database already exists!" -ForegroundColor Green
        } else {
            Write-Host "API call failed: $errorMessage" -ForegroundColor Red
            Write-Host ""
            Write-Host "Falling back to manual console creation..." -ForegroundColor Yellow
            Start-Process "https://console.firebase.google.com/project/canma-wallet/database"
            Write-Host ""
            Write-Host "Please:" -ForegroundColor Yellow
            Write-Host "1. Click 'Create Database' in the opened browser" -ForegroundColor White
            Write-Host "2. Select location: asia-southeast1" -ForegroundColor White
            Write-Host "3. Choose 'Start in test mode'" -ForegroundColor White
            Write-Host "4. Click 'Enable'" -ForegroundColor White
            Write-Host ""
            Write-Host "After database is created, run:" -ForegroundColor Yellow
            Write-Host "  firebase deploy --only database" -ForegroundColor White
            exit 1
        }
    }
} else {
    Write-Host "Could not get Firebase token automatically." -ForegroundColor Red
    Write-Host ""
    Write-Host "Opening Firebase Console for manual setup..." -ForegroundColor Yellow
    Start-Process "https://console.firebase.google.com/project/canma-wallet/database"
    Write-Host ""
    Write-Host "Please:" -ForegroundColor Yellow
    Write-Host "1. Click 'Create Database' in the opened browser" -ForegroundColor White
    Write-Host "2. Select location: asia-southeast1" -ForegroundColor White
    Write-Host "3. Choose 'Start in test mode'" -ForegroundColor White
    Write-Host "4. Click 'Enable'" -ForegroundColor White
    Write-Host ""
    Write-Host "After database is created, run:" -ForegroundColor Yellow
    Write-Host "  firebase deploy --only database" -ForegroundColor White
    exit 1
}

# Wait a bit for database to be ready
Write-Host ""
Write-Host "Waiting for database to be ready..." -ForegroundColor Yellow
Start-Sleep -Seconds 15

# Deploy rules
Write-Host ""
Write-Host "Step 3: Deploying security rules..." -ForegroundColor Cyan
firebase deploy --only database --project $PROJECT_ID

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "=== SUCCESS ===" -ForegroundColor Green
    Write-Host "✓ Realtime Database created" -ForegroundColor Green
    Write-Host "✓ Security rules deployed" -ForegroundColor Green
    Write-Host ""
    Write-Host "Database URL: https://$PROJECT_ID-default-rtdb.asia-southeast1.firebasedatabase.app" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "1. Run: flutter run" -ForegroundColor White
    Write-Host "2. Test Near Sync feature in app" -ForegroundColor White
} else {
    Write-Host ""
    Write-Host "Rules deployment failed. Please try manually:" -ForegroundColor Red
    Write-Host "  firebase deploy --only database" -ForegroundColor White
}
