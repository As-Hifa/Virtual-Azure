resource "azurerm_mysql_flexible_server" "sql-server" {
  name                   = "sql-server1"
  resource_group_name    = azurerm_resource_group.sido-pro.name
  location               = azurerm_resource_group.sido-pro.location
  administrator_login    = "mysqladminun"
  administrator_password = "H@Sh1CoR3!"
  sku_name               = "B_Standard_B1s"
  delegated_subnet_id    = azurerm_subnet.sql-subnet.id
  private_dns_zone_id    = azurerm_private_dns_zone.dns-sql.id
  depends_on = [
    azurerm_subnet.sql-subnet,
    azurerm_private_dns_zone_virtual_network_link.link-sql
  ]
}


resource "azurerm_mysql_flexible_database" "my-sql" {
  name                = "mysql-db"
  resource_group_name = azurerm_resource_group.sido-pro.name
  server_name         = azurerm_mysql_flexible_server.sql-server.name
  charset             = "utf8"
  collation           = "utf8_unicode_ci"
  depends_on = [
    azurerm_mysql_flexible_server.sql-server
  ]
}

resource "azurerm_private_endpoint" "endpoint_to_sql" {
  name                = "endpoint_to_sql"
  location            = azurerm_resource_group.sido-pro.location
  resource_group_name = azurerm_resource_group.sido-pro.name
  subnet_id           = azurerm_subnet.sql-subnet.id
  depends_on = [
    azurerm_subnet.sql-subnet
  ]

  private_service_connection {
    name                           = "privateserviceconnection"
    private_connection_resource_id = azurerm_mysql_flexible_server.sql-server.id
    subresource_names              = [ "mysqlServer" ]
    is_manual_connection           = false
  }
}

resource "azurerm_private_dns_zone" "dns-sql" {
  name                = "dns-sql.mysql.database.azure.com"
  resource_group_name = azurerm_resource_group.sido-pro.name
}


resource "azurerm_private_dns_zone_virtual_network_link" "link-sql" {
  name                  = "mysqlfsVnetZonecom"
  private_dns_zone_name = azurerm_private_dns_zone.dns-sql.name
  resource_group_name   = azurerm_resource_group.sido-pro.name
  virtual_network_id    = azurerm_virtual_network.vnet-1.id
}