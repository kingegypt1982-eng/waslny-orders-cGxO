-- AlterTable
ALTER TABLE "PricingSettings" ADD COLUMN     "paymentFeeFixed" DECIMAL(10,2) NOT NULL DEFAULT 0,
ADD COLUMN     "paymentFeePercent" DECIMAL(5,2) NOT NULL DEFAULT 2.5;

-- AlterTable: new columns arrive nullable so existing TopUp rows survive...
ALTER TABLE "TopUp" ADD COLUMN     "chargeAmount" DECIMAL(12,2),
ADD COLUMN     "creditAmount" DECIMAL(12,2),
ADD COLUMN     "feeAmount" DECIMAL(12,2),
ADD COLUMN     "feeFixed" DECIMAL(10,2),
ADD COLUMN     "feePercent" DECIMAL(5,2);

-- ...then legacy rows are backfilled as fee-free (charge = credit, fee = 0)...
UPDATE "TopUp" SET "creditAmount" = "amount", "chargeAmount" = "amount", "feeAmount" = 0, "feeFixed" = 0, "feePercent" = 0 WHERE "creditAmount" IS NULL;

-- ...and only then constrained to NOT NULL.
ALTER TABLE "TopUp" ALTER COLUMN "chargeAmount" SET NOT NULL,
ALTER COLUMN "creditAmount" SET NOT NULL,
ALTER COLUMN "feeAmount" SET NOT NULL,
ALTER COLUMN "feeFixed" SET NOT NULL,
ALTER COLUMN "feePercent" SET NOT NULL;
