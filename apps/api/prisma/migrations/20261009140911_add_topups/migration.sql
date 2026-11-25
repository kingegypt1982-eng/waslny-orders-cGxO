-- CreateEnum
CREATE TYPE "TopUpStatus" AS ENUM ('PENDING', 'SUCCEEDED', 'FAILED', 'EXPIRED');

-- AlterTable
ALTER TABLE "PricingSettings" ADD COLUMN     "maxTopUpAmount" DECIMAL(12,2) NOT NULL DEFAULT 10000,
ADD COLUMN     "minTopUpAmount" DECIMAL(10,2) NOT NULL DEFAULT 50;

-- AlterTable
ALTER TABLE "WalletTransaction" ADD COLUMN     "topUpId" TEXT;

-- CreateTable
CREATE TABLE "TopUp" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "amount" DECIMAL(12,2) NOT NULL,
    "currency" TEXT NOT NULL DEFAULT 'EGP',
    "status" "TopUpStatus" NOT NULL DEFAULT 'PENDING',
    "providerSessionId" TEXT,
    "providerOrderRef" TEXT NOT NULL,
    "providerTransactionId" TEXT,
    "checkoutUrl" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "paidAt" TIMESTAMP(3),
    "failureReason" TEXT,

    CONSTRAINT "TopUp_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "TopUp_providerOrderRef_key" ON "TopUp"("providerOrderRef");

-- CreateIndex
CREATE UNIQUE INDEX "TopUp_providerTransactionId_key" ON "TopUp"("providerTransactionId");

-- CreateIndex
CREATE INDEX "TopUp_userId_createdAt_idx" ON "TopUp"("userId", "createdAt");

-- CreateIndex
CREATE INDEX "TopUp_status_createdAt_idx" ON "TopUp"("status", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "WalletTransaction_topUpId_key" ON "WalletTransaction"("topUpId");

-- AddForeignKey
ALTER TABLE "WalletTransaction" ADD CONSTRAINT "WalletTransaction_topUpId_fkey" FOREIGN KEY ("topUpId") REFERENCES "TopUp"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "TopUp" ADD CONSTRAINT "TopUp_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

