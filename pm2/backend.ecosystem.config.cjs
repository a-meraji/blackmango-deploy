module.exports = {
  apps: [
    {
      name: "bbm-backend",
      cwd: "/var/www/big_black_mango/backend",
      script: "dist/main.js",
      exec_mode: "fork",
      instances: 1,
      autorestart: true,
      watch: false,
      max_memory_restart: "500M",
      env_staging: {
        NODE_ENV: "staging",
      },
      env_production: {
        NODE_ENV: "production",
      },
    },
  ],
};

