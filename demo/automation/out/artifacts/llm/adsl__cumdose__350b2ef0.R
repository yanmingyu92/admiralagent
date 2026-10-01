# DISCLAIMER: DRAFT CODE - qualified human review required before use.
# ---- CUMDOSE | NEEDS HUMAN REVIEW ----
# Spec origin: "For ARMN=0 or 1: CUMDOSE=TRT01PN*TRTDUR. --- For ARMN=2: CUMDOSE will be based on 54mg per day for the # of days subj was in 1st dosing interval (i.e., visit4date-TRTSTDT+1 if 1st interval completed, TRTEDT-TRTSTDT+1 if subj discontinued <=visit 4 and > visit 3), 81mg per day for the # of days subj was in 2nd dosing interval (i.e., visit12date-visit4date if 2nd interval completed, TRTEDT-visit4date if subj discontinued <= visit 12 and > visit 4), and 54mg per day for the # of days subj was in 3rd dosing interval (i.e., TRTEDT - visit12date if subj continued after visit 12)."
# Rationale: Derivation is a complex multi-branch conditional dependent on ARMN, scheduled visit dates (visit4date, visit12date), dosing intervals and discontinuation logic; not expressible with the allowed operations.
# No code generated: this derivation requires a human decision.
# CHECK: statistician decides rule, then reclassify or hand-write.
