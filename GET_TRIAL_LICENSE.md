# Get Vault Enterprise Trial License

## Steps to get your 30-day trial license:

1. Visit: https://www.hashicorp.com/products/vault/trial

2. Fill out the form with your information

3. You'll receive an email with your trial license

4. Copy the license content and save it as `vault.hclic` in this directory

5. The license file should look like this:
   ```
   02MV4UU43BK5HGYYTOJZWFQMTMNNEWG33JLJSWKZTVNZAWMU3FPBXKQZLONJXXGYLCOVRXGULTDK5WWWZTVNRJQ...
   ```

6. Restart the containers:
   ```bash
   docker-compose restart
   ```

7. Run the initialization script:
   ```bash
   ./vault-init.sh
   ```

## Alternative: Manual License Application

If you already have the containers running, you can apply the license manually:

```bash
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=myroot
vault write sys/license text=@vault.hclic
```