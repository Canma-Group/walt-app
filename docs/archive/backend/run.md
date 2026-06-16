cd C:\MyDream\Kandidat wallet\bangkingt_app_backend
# Start PostgreSQL + compile + run server
npm start
# OR manual steps:
docker-compose up -d     # Start PostgreSQL
npm run build            # Compile TypeScript  
node lib/server.js       # Run server on p