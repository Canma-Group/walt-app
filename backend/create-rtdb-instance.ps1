# Script untuk membuat Firebase Realtime Database instance via REST API
# Requires: gcloud CLI authenticated

$PROJECT_ID = "canma-wallet"
$LOCATION = "asia-southeast1"
$DATABASE_ID = "canma-wallet-default-rtdb"

Write-Host "Creating Realtime Database instance..." -ForegroundColor Yellow

# Enable Firebase Database API
gcloud services enable firebasedatabase.googleapis.com --project=$PROJECT_ID

# Get access token
$TOKEN = gcloud auth print-access-token

# Create database instance
$BODY = @{
    "type" = "USER_DATABASE"
    "state" = "ACTIVE"
} | ConvertTo-Json

$HEADERS = @{
    "Authorization" = "Bearer $TOKEN"
    "Content-Type" = "application/json"
}

$URL = "https://firebasedatabase.googleapis.com/v1beta/projects/$PROJECT_ID/locations/$LOCATION/instances?databaseId=$DATABASE_ID"

try {
    $response = Invoke-RestMethod -Uri $URL -Method POST -Headers $HEADERS -Body $BODY
    Write-Host "✓ Database instance created successfully!" -ForegroundColor Green
    Write-Host $response
    
    # Wait for instance to be ready
    Write-Host "Waiting for instance to be ready..." -ForegroundColor Yellow
    Start-Sleep -Seconds 10
    
    # Deploy rules
    Write-Host "Deploying rules..." -ForegroundColor Yellow
    firebase deploy --only database
    
    Write-Host "✓ Setup complete!" -ForegroundColor Green
} catch {
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host "Please create database manually via Firebase Console" -ForegroundColor Yellow
}
