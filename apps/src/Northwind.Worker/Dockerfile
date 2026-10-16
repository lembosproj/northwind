FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY Directory.Build.props global.json ./
COPY src/Northwind.Runtime/ src/Northwind.Runtime/
COPY src/Northwind.Worker/ src/Northwind.Worker/
RUN dotnet publish src/Northwind.Worker -c Release -o /app

FROM mcr.microsoft.com/dotnet/runtime:10.0
WORKDIR /app
COPY --from=build /app .
USER $APP_UID
ENTRYPOINT ["dotnet", "Northwind.Worker.dll"]
