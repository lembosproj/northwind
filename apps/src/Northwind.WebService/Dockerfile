FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY Directory.Build.props global.json ./
COPY src/Northwind.Runtime/ src/Northwind.Runtime/
COPY src/Northwind.WebService/ src/Northwind.WebService/
RUN dotnet publish src/Northwind.WebService -c Release -o /app

FROM mcr.microsoft.com/dotnet/aspnet:10.0
WORKDIR /app
COPY --from=build /app .
EXPOSE 8080
ENV ASPNETCORE_HTTP_PORTS=8080
USER $APP_UID
ENTRYPOINT ["dotnet", "Northwind.WebService.dll"]
