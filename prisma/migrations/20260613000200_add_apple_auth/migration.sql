ALTER TABLE "User" ADD COLUMN "appleSubject" TEXT;
ALTER TABLE "User" ADD COLUMN "authProvider" TEXT NOT NULL DEFAULT 'email';
ALTER TABLE "User" ALTER COLUMN "passwordHash" DROP NOT NULL;

CREATE UNIQUE INDEX "User_appleSubject_key" ON "User"("appleSubject");
CREATE INDEX "User_authProvider_idx" ON "User"("authProvider");
