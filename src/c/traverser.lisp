;;;; Common traverser functions for pretty printing and other tasks.

(in-package :cm-c)

;;; A traverser which checks the identifier for c-conformity
;;; and automatically solves naming problems.
(defclass renamer ()
  ((used-names :initform (make-hash-table :test 'equal))
   (name-map :initform (make-hash-table :test 'equal))))
(defgeneric check-and-get-name (renamer check-name))

;;; Check if identifier is OK.
;;; Store in hash table and correct if necessary.
(defmethod check-and-get-name ((item renamer) check-name)
  (with-slots (used-names name-map) item
    (if (eql check-name '|...|)
        ;; ignore '...'
        check-name
        ;; treat hyphen and underscore equally / map hyphen to underscore
        (let* ((name-string (symbol-name check-name))
               (identifier (substitute #\_ #\- name-string)))
          (when (and (not (equal identifier name-string))
                     (find :hyphen *enabled-warnings*))
            (warn "Possible ambiguity through hyphen override of ~s" check-name))
          (let ((alr-checked (gethash identifier name-map)))
           (if alr-checked
               alr-checked
               (labels ((check-char (x) (alpha-char-p x))
                        (check-underscore (x) (eql #\_ x))
                        (check-tilde (x) (eql #\~ x))
                        (check-num (x) (digit-char-p x))
			(check-hex (x) (and (eql #\0 (first x))
					    (or (eql #\x (second x))
						(eql #\X (second x)))))
                        (check-all (x)
                         (or
                           (check-char x)
                           (check-underscore x)
                           (check-num x)))
                        (check-nall (x)
                          (not (check-all x))))
                 (let* ((identifier-l (concatenate 'list identifier))
                        (changed-l (if (check-tilde (car identifier-l))
                                       (concatenate 'list
                                         '(#\~)
                                         (substitute-if #\_ #'check-nall (rest identifier-l)))
				       (substitute-if #\_ #'check-nall identifier-l)))
                        (changed (concatenate 'string changed-l)))

                   (when (and (check-num (first changed-l))
			      (not (check-hex changed-l)))
                     (setf (first changed-l) #\_)
                     (setf changed (concatenate 'string changed-l)))

                   (loop while (gethash changed used-names) do
                     (setf changed (format nil "_~a" changed)))
                   (setf (gethash changed used-names) t)
                   (setf changed (intern changed))
                   (setf (gethash identifier name-map) changed)
                   changed))))))))

;;; Traverses the tree but checks only the identifier nodes.
(defmethod traverser ((rn renamer) (item identifier) level)
  (declare (ignore level))
  (with-slots (identifier) item
    ;(setf identifier (check-and-get-name rn (intern (symbol-name identifier) :cgen)))))
    (setf identifier (check-and-get-name rn identifier)))) ;(intern (symbol-name identifier))))))

;;; This Traverser checks whether braces really are necessary.
(defclass decl-blocker ()
  ((names :initform `(,(make-hash-table)))
   (delta-names :initform '(nil))
   (in-decl :initform '(nil))
   (in-decl-item :initform '(nil))
   (make-block :initform '(nil))))

(defmethod traverser ((db decl-blocker) (item identifier) level)
  "find names, check if in decl-item, save infos on stack in decl-blocker"
  (declare (ignore level))
  (with-slots (identifier) item
    (with-slots (names delta-names in-decl-item make-block) db
      (when (first in-decl-item)
	(if (gethash identifier (first names))
	    (setf (first make-block) t)
	    (progn (push identifier (first delta-names))
		   (setf (gethash identifier (first names)) t)))))))

(with-proxynodes (proxy)
  "find declaration-item identifier"
  
  (defproxymethod :before (db decl-blocker) proxy
    "push 'true' on in-decl stack in decl-blocker"
    (with-slots (in-decl in-decl-item) db
      (when (first in-decl)
	(setf (first in-decl-item) t))))

  (defproxymethod :after (db decl-blocker) proxy
    "pop last item on in-decl stack of decl-blocker"
    (with-slots (in-decl in-decl-item) db
      (when (first in-decl)
	(setf (first in-decl-item) nil))))
  
  (defmethod traverser :before ((db decl-blocker) (item declaration-item) level)
    "prepare decl-blocker-proxy to identify names"
    (declare (ignore level))
    (with-slots (identifier) item
      (make-proxy identifier proxy)))
  
  (defmethod traverser :after ((db decl-blocker) (item declaration-item) level)
    "remove decl-blocker-proxy"
    (declare (ignore level))
    (with-slots (identifier) item
      (del-proxy identifier)))
)

(with-proxynodes (tmp-proxy)
  "find genuine identifier in array reference"
  
  (defproxymethod :before (db decl-blocker) tmp-proxy 
    "array[indizes] -> both are 'name', set 'false' for indizes on stack"
    (with-slots (in-decl in-decl-item) db
      (if (first in-decl)
	  (push nil in-decl-item))))

  (defproxymethod :after (db decl-blocker) tmp-proxy
    "pop last item on in-decl stack of decl-blocker"
    (with-slots (in-decl in-decl-item) db
      (if (first in-decl)
	  (pop in-decl-item))))

  (defmethod traverser :before ((db decl-blocker) (item array-reference) level)
    "add proxy do distinct array from indizes"
    (declare (ignore level))
    (with-slots (indizes) item
      (make-proxy indizes tmp-proxy)))

  (defmethod traverser :after ((db decl-blocker) (item array-reference) level)
    "remove proxy..."
    (declare (ignore level))
    (with-slots (indizes) item
      (del-proxy indizes)))
)

(with-proxynodes (funcall-args)
  "identify parameters in function call (similar to arrey/indizes)"

  (defmethod traverser :before ((db decl-blocker) (item function-call) level)
    "add proxy"
    (declare (ignore level))
    (with-slots (arguments)
      (make-proxy arguments funcall-args)))

  (defmethod traverser :after ((db decl-blocker) (item function-call) level)
    "remove proxy"
    (declare (ignore level))
    (with-slots (arguments)
      (del-proxy arguments)))

  (defproxymethod :before (db decl-blocker) funcall-args
    "(constructor arg1 arg2..) -> 'constructor', 'arg1', 'arg2' are identifier -> hide args"
    (with-slots (in-decl in-decl-item) db
      (when (first in-decl)
	(push nil in-decl-item))))

  (defproxymethod :after (db decl-blocker) funcall-args
    "pop last item from in-decl stack of decl-blocker"
    (with-slots (in-decl in-decl-item) db
      (when (first in-decl)
	(pop in-decl-item)))))
	     
	     

(defmethod traverser :before ((db decl-blocker) (item declaration-list) level)
  "prepare empty lists and a nil-value for further traversing"
  (declare (ignore level))
  (with-slots (delta-names make-block in-decl in-decl-item) db
    (push nil delta-names)
    (push nil make-block)
    (push t in-decl)
    (push nil in-decl-item)))

(defmethod traverser :after ((db decl-blocker) (item declaration-list) level)
  "check values in decl-blocker and set braces to 'true' or 'nil'"
  (declare (ignore level))
  (with-slots (names delta-names make-block in-decl in-decl-item) db
    (if (first make-block)
	(progn
	  (setf (slot-value item 'braces) t)
	  (loop for i in (first delta-names) do
	       (setf (gethash i (first names)) nil)))
	(if (> (list-length delta-names) 1)
	    (progn
	      (setf (slot-value item 'braces) nil)
	      (loop for i in (first  delta-names) do
		(push i (second delta-names))))))
    (pop delta-names)
    (pop make-block)
    (pop in-decl)
    (pop in-decl-item)))

(defmacro prepare-blocker-stacks (node-class)
  "create method which prepares decl-blocker stacks"
  `(defmethod traverser :before ((db decl-blocker) (item ,node-class) level)
     "prepare empty decl-blocker stacks and values"
     (declare (ignore level))
     (with-slots (names) db
       (push (make-hash-table) names))))

(defmacro clean-blocker-stacks (node-class)
  "creates method which cleans decl-blocker stacks"
  `(defmethod traverser :after ((db decl-blocker) (item ,node-class) level)
     "clean up decl-blocker stack and values"
     (declare (ignore level))
     (with-slots (names) db
       (pop names))))

(defmacro decl-blocker-extra-nodes (&rest nodes)
  `(progn .,(loop for i in nodes collect
	      `(progn (eval (prepare-blocker-stacks ,i))
	      	      (eval (clean-blocker-stacks ,i))))))

(decl-blocker-extra-nodes function-definition struct-definition for-statement compound-statement)

;;; This traverser hides "{}" in ifs where possible
(defclass if-blocker ()
  ((parent-node :initform '())
   (statement-count :initform '(0))
   (first-statement :initform '(nil))
   (self-else :initform '(nil))
   (child-else :initform '(nil))
   (force-braces :initform '(nil))
   (curr-level :initform '())))
		 

(with-proxynodes (if-proxy else-proxy)
  "use proxy nodes for if and else body in if-statements"

  (defmethod traverser :before ((ib if-blocker) (item if-statement) level)
    "add proxy-node to if- and else-body; add stack infos; check nested-if"
    (declare (ignore level))
    (with-slots (if-body else-body) item
      (with-slots (self-else child-else) ib
	(if else-body
	    (progn
	      (make-proxy else-body else-proxy)
	      (push t self-else)
	      (setf (first child-else) t))
	    (progn
	      (push nil self-else)
	      (setf (first child-else) nil)))
	(push 'unknown child-else) ;;handled like t, better debug-output
  	(make-proxy if-body if-proxy))))
  
  (defmethod traverser :after ((ib if-blocker) (item if-statement) level)
    "clean up proxy-nodes and stack"
    (declare (ignore level))
    (with-slots (if-body else-body) item
      (with-slots (self-else child-else) ib
  	(del-proxy if-body)
	(if else-body
	    (del-proxy else-body))
	(pop child-else)
	(pop self-else))))
  
  (defproxymethod :before (ib if-blocker) if-proxy
    "push 'if-body info on stack"
    (with-slots (parent-node) ib
      (push 'if-body parent-node)))
  
  (defproxymethod :after (ib if-blocker) if-proxy
    "pop stack"
    (with-slots (parent-node) ib
      (pop parent-node)))
  
  (defproxymethod :before (ib if-blocker) else-proxy
    "push 'else-body info on stack"
    (with-slots (parent-node) ib
      (push 'else-body parent-node)))
  
  (defproxymethod :after (ib if-blocker) else-proxy
    "pop stack"
    (with-slots (parent-node) ib
      (pop parent-node)))
)

(defmethod traverser :before ((ib if-blocker) (item compound-statement) level)
  "prepare stacks, count statements"
  (with-slots (parent-node statement-count first-statement force-braces curr-level) ib
    (with-slots (statements) item
      (push level curr-level)
      (push t first-statement)
      (push 'compound-statement parent-node)
      (push nil force-braces)
      (push 0 statement-count))))

(defmethod traverser :after ((ib if-blocker) (item compound-statement) level)
  "decide wheter to print braces or not"
  (with-slots (parent-node statement-count first-statement
	       self-else child-else force-braces curr-level) ib
    (with-slots (statement braces) item
      (pop parent-node)
      (pop curr-level)
	  
      (cond ((eql (first parent-node) 'if-body)
			 
	     (cond ((and (< (first statement-count) 2)
			 (not (first self-else)))
		    (setf braces nil))
		   ((and (< (first statement-count) 2)
			 (first self-else)
			 (first child-else))
		    (setf braces nil))))
			
	    ((eql (first parent-node) 'else-body)
	     (if (< (first statement-count) 2)
		 (setf braces nil))))
	  
      (if (first force-braces)
	  (setf braces t))
      (pop statement-count)
      (pop first-statement)
      (pop force-braces))))

(defmethod traverser :after ((ib if-blocker) (item comment) level)
  "force braces if comments are present / important for solitary comments"
  (declare (ignore level))
  (with-slots (force-braces) ib
    (setf (first force-braces) t)))

(defmethod traverser :before ((ib if-blocker) (item declaration-list) level)
  "set force-braces (to t) if declartion-list found"
  (declare (ignore level))
  (with-slots (force-braces) ib
    (if force-braces
	(setf (first force-braces) t))))

(defmethod traverser :before ((ib if-blocker) (item nodelist) level)
  "check nodelists that belong to a compound-statement"
  (with-slots (statement-count first-statement parent-node curr-level) ib
    (with-slots (nodes) item
      (when (and (first first-statement)
      		 (eql (first parent-node) 'compound-statement) 
		 (eql (- level (first curr-level)) 2))
		
	(let ((count (length nodes)))
	  (setf (first first-statement) nil)
	  (setf (first statement-count)
		(max count (first statement-count))))))))


(defmethod traverser :after ((ib if-blocker) (item expression-statement) level)
  "place semicolon at empty branches"
  (with-slots (statement-count curr-level force-braces) ib
    (with-slots (force-semicolon expression) item
      (if (and
	   ;; subnode that can contain no further statements
	   (typep expression 'nodelist)
	   ;; do nothing if a comment is present, see above (if-blocker comment)
	   (not (eql (first force-braces) t))
	   ;; specific position in ast, 1st expr-statement in body.
	   (and (first curr-level) ;; curr-level must be set
		(eql (- level (first curr-level)) 1))
	   ;; subtree has no expressions
	   ;; this is a :after method, statement-cound already filled
	   (eql (first statement-count) 0))
	  (setf force-semicolon t)))))


;;; This traveser removes ambiguous nested compound-statements in else-if
;;; to reduce indentation.
(defclass else-if-traverser ()())
(with-proxynodes (else-if-proxy)
  "use proxy nodes for else-if occurences"
  
  (defmethod traverser :before ((eit else-if-traverser) (item if-statement) level)
    "add else-if-proxy to else-body"
    (declare (ignore level))
    (with-slots (else-body) item
      (if else-body
	  (make-proxy else-body else-if-proxy))))

  (defmethod traverser :after ((eit else-if-traverser) (item if-statement) level)
    "clean up proxy nodes (else-if-proxy"
    (declare (ignore level))
    (with-slots (else-body) item
      (if else-body
	  (del-proxy else-body))))

  (defproxymethod :before (eit else-if-traverser) else-if-proxy
    "check if only one single if-statement is present in else-body and remove compound-statement node"
    (with-slots (proxy-subnode) item
      (let ((subnode (slot-value (slot-value proxy-subnode 'statements) 'expression)))
	(when (typep subnode 'if-statement)
	  (setf proxy-subnode subnode))))))

;;; Remove nested nodelists (progn (progn (progn ...)))
;;; Required for proper placement of curly braces (esp. for if-else)
(defclass nested-nodelist-remover ()())
(defmethod traverser :after ((nnr nested-nodelist-remover) (item nodelist) level)
  (with-slots (nodes) item
    (when (and (eql (length nodes) 1)
	       (typep (first nodes) 'expression-statement)
	       (typep (slot-value (first nodes) 'expression) 'nodelist))
      (setf nodes (slot-value (slot-value (first nodes) 'expression) 'nodes)))))



