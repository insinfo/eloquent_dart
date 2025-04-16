<?php

//$dsn = 'pgsql:dbname=siamweb;host=127.0.0.1';
//$user = 'dart';
//$password = 'dart';

//$pdo = new PDO($dsn, $user, $password);
//$result = $pdo->query('select "nome" from esic.lda_solicitante where "idsolicitante" = 3 limit 1')->fetch(PDO::FETCH_NUM);
//statement: DEALLOCATE pdo_stmt_00000001
// $st = $pdo->prepare('select "nome" from esic.lda_solicitante where "idsolicitante" = ? limit 1');
// $st->execute([3]);
// $result = $st->fetch(PDO::FETCH_NUM);

// Desabilita a exibição de E_DEPRECATED e E_NOTICE  & ~E_NOTICE
error_reporting(E_ALL & ~E_DEPRECATED );

require 'C:/MyPhpProjects/teste_query_builder/vendor_5.2/autoload.php';

use Illuminate\Database\Capsule\Manager;
use Illuminate\Support\Arr;
use Illuminate\Support\Fluent;
use Illuminate\Container\Container;
use Illuminate\Support\Str;

$capsule = new Manager;
$capsule->setFetchMode(PDO::FETCH_ASSOC);
$capsule->addConnection([
    'driver' => 'pgsql',
    'host' => 'localhost',
    'port' => '5432',
    'database' => 'siamweb',
    'username' => 'dart',
    'password' => 'dart',
    'charset' => 'utf8',
    'prefix' => '',
    'schema' => ['public'],    
]);

$capsule->setAsGlobal();
$db = $capsule->connection();


$organogramaId = 1068;

$organogramaId = 1068;

// --- Defina a lógica da subconsulta usando DB::raw para correlação ---
// !!! Precisamos passar $db para dentro do escopo da Closure !!!
$subQueryNomePai = function ($query) use ($db) {
    $query->select('ohp.nome')
        ->from('organograma_historico as ohp')
        // Condição 1: Use where + raw para comparar com a coluna externa oh.id_pai
        ->where('ohp.id_organograma', '=', $db->raw('"oh"."id_pai"')) // PostgreSQL usa aspas duplas para identificadores
        // Condição 2: Use where + raw na subconsulta aninhada também
        ->where('ohp.data_inicio', function ($subQuery) use ($db) { // !!! Passe $db para a sub-closure também !!!
            $subQuery->selectRaw('max(s.data_inicio)')
                     ->from('organograma_historico as s')
                     // Correlação com where + raw
                     ->where('s.id_organograma', '=', $db->raw('"oh"."id_pai"'))
                     // Correlação com where + raw (atenção ao operador <=)
                     ->where('s.data_inicio', '<=', $db->raw('"oh"."data_inicio"'));
        })
        ->limit(1);
};

// --- Construa a query principal (esta parte não muda) ---
$resultados = $db->table('organograma as o')
    ->join('organograma_historico as oh', 'oh.id_organograma', '=', 'o.id')
    ->select('oh.*', 'o.ativo')
    ->selectSub($subQueryNomePai, 'nomeOrganogramaPai')
    ->where('o.id', $organogramaId)
    ->orderBy('oh.data_inicio', 'desc')
    ->get();

// --- Loop de resultados (não muda) ---
foreach ($resultados as $resultado) {
    echo "ID Histórico: " . $resultado['id'] . ", Nome Pai: " . $resultado['nomeOrganogramaPai'] . "\n";
}
 
//print_r($result);