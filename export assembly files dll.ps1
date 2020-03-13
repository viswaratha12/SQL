#[Reflection.Assembly]::LoadWithPartialName("Microsoft.SQLServer.ManagedDTS") | out-null
 
$assemblyListQuery = "SELECT A.name FROM sys.assemblies A WHERE A.is_user_defined = 1 ORDER BY 1 ASC "
 
$queryTemplate = "
SELECT 
    AF.content
,    A.name    
FROM 
    sys.assembly_files AF 
    INNER JOIN 
        sys.assemblies A 
        ON AF.assembly_id = A.assembly_id 
WHERE 
    AF.file_id = 1
    AND A.is_user_defined = 1
    --AND A.name = @assemblyName
"
 
Function Save-Assemblies()
{
   param
   (
      [string]$connectionString,
      [string]$query
   )
   $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
   $command = New-Object System.Data.SqlClient.SqlCommand($query)

   $connection.Open()
   $command.Connection = $connection
   #$hush = $command.Parameters.AddWithValue("@assemblyName", $assemblyName)
   $reader = $command.ExecuteReader()

   while ($reader.Read())
   {
      #$bytes = New-Object System.Data.SqlClient.SqlBytes()
      $bytes = $reader.GetSqlBytes(0)
      $name = $reader.GetString(1)
      $bytestream = New-Object System.IO.FileStream("C:\CR\$name.dll", [System.IO.FileMode]::Create)
      $bytestream.Write($bytes.Value, 0, $bytes.Length)
      $bytestream.Close()
   }
            
}
 
 
$bnode = "Data Source=CMDPRODSQL01\CMD01,11982;Initial Catalog=CommanderWarehouse;Integrated Security=SSPI;"
 
$assemblyName = "PhoenixInteractive.Commander.Database.Clr.CommanderWarehouse.Common"
    
Save-Assemblies $bnode $queryTemplate
