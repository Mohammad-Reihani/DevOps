# How?

Bro, just take it do what ever you want, just put it in nginx config file (it was in a file named backup. do not forget to backup current config!)

```bash
server {
    listen 80;
    server_name subdomain.domain.com;

    # Frontend Service for First Website
    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Redirect to default server on 5xx errors
        error_page 500 502 503 504 505 506 507 508 510 511 = @redirect_down;
    }

    # Redirect location to handle error redirection
    location @redirect_down {
        return 302 https://errorsubdomain.domain.com/503/1/index.html;  # Replace with the actual address or IP of your default server
    }

    # Security Headers
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Content-Type-Options "nosniff";
}




server {
    listen 80;
    server_name backenddomain.domain.com;

    # Backend Service for First Website
    location / {
        proxy_pass http://localhost:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Redirect to default server on 5xx errors
        error_page 500 502 503 504 505 506 507 508 510 511 = @redirect_down;
    }

    location @redirect_down {
        return 302 https://errorsubdomain.domain.com/503/1/index.html;  # Replace with the actual address or IP of your default server
    }


    # Security Headers
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Content-Type-Options "nosniff";
}


# Server to handle the errors redirected
server {
    listen 80;
    server_name errorsubdomain.domain.com;

    root /someLocationOnLinuxOfCourse/statics/errors;  # Set the root directory for static error files

    location / {
        try_files $uri.html $uri @redirect_down;  # Look for the error file, if not found fallback to index.html
    }

    location @redirect_down {
        return 302 https://errorsubdomain.domain.com/404/1/index.html;  # Replace with the actual address or IP of your default server
    }

    # Security Headers
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Content-Type-Options "nosniff";
}



# Default Server Block to Handle Unmatched Request
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name _;

    root /someLocationOnLinuxOfCourse/statics/errors/404/1;  # Set the root directory

    location / {
        try_files $uri /index.html;
    }

    # Security Headers
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Content-Type-Options "nosniff";
}



# here are the mail configs ***********************************************
# well, this is not well documented, I suggest you check it while doing a mail server ok?

server {
   listen 80;
   server_name mail.domain.com;

    Redirect all HTTP traffic to HTTPS
   location / {
       return 301 https://$host$request_uri;
   }
}

server {
   listen 443 ssl;
   server_name mail.domain.com;

   # This is how you set SSL shit, not detailed tho, gonna cover it somewhere else
   ssl_certificate /etc/letsencrypt/live/domain.com/fullchain.pem;
   ssl_certificate_key /etc/letsencrypt/live/domain.com/privkey.pem;

   ssl_protocols TLSv1.2 TLSv1.3;
   ssl_prefer_server_ciphers on;
   ssl_ciphers 'ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';

   location / {
       proxy_pass https://localhost:1443;
       proxy_set_header Host $host;
       proxy_set_header X-Real-IP $remote_addr;
       proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
       proxy_set_header X-Forwarded-Proto $scheme;

        Redirect to default server on 5xx errors
       error_page 500 502 503 504 505 506 507 508 510 511 = @redirect_down;
   }

   location @redirect_down {
       return 302 https://errorsubdomain.domain.com/503/1/index.html;
   }

    Security Headers
   add_header X-Frame-Options "SAMEORIGIN";
   add_header X-XSS-Protection "1; mode=block";
   add_header X-Content-Type-Options "nosniff";
}
```
